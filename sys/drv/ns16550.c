#define KL_LOG KL_DEV
#include <sys/libkern.h>
#include <sys/spinlock.h>
#include <sys/vnode.h>
#include <sys/devfs.h>
#include <sys/klog.h>
#include <sys/condvar.h>
#include <sys/ringbuf.h>
#include <sys/pci.h>
#include <sys/termios.h>
#include <sys/ttycom.h>
#include <dev/isareg.h>
#include <dev/ns16550reg.h>
#include <sys/interrupt.h>
#include <sys/stat.h>
#include <sys/devclass.h>
#include <sys/tty.h>
#include <sys/priority.h>
#include <sys/sched.h>

#define UART_BUFSIZE 128

typedef struct ns16550_state {
  spin_t lock;
  ringbuf_t tx_buf, rx_buf;
  intr_handler_t intr_handler;
  resource_t *regs;
  tty_t *tty;
  condvar_t tty_thread_cv;
  uint8_t tty_ipend;
  bool tty_outq_nonempty;
} ns16550_state_t;

#define in(regs, offset) bus_read_1((regs), (offset))
#define out(regs, offset, value) bus_write_1((regs), (offset), (value))

static void set(resource_t *regs, unsigned offset, uint8_t mask) {
  out(regs, offset, in(regs, offset) | mask);
}

static void clr(resource_t *regs, unsigned offset, uint8_t mask) {
  out(regs, offset, in(regs, offset) & ~mask);
}

static void setup(resource_t *regs) {
  set(regs, LCR, LCR_DLAB);
  out(regs, DLM, 0);
  out(regs, DLL, 1); /* 115200 */
  clr(regs, LCR, LCR_DLAB);

  out(regs, IER, 0);
  out(regs, FCR, 0);
  out(regs, LCR, LCR_8BITS); /* 8-bit data, no parity */
}

static intr_filter_t ns16550_intr(void *data) {
  ns16550_state_t *ns16550 = data;
  resource_t *uart = ns16550->regs;
  intr_filter_t res = IF_STRAY;

  WITH_SPIN_LOCK (&ns16550->lock) {
    uint8_t iir = in(uart, IIR);

    /* data ready to be received? */
    if (iir & IIR_RXRDY) {
      (void)ringbuf_putb(&ns16550->rx_buf, in(uart, RBR));
      ns16550->tty_ipend |= IIR_RXRDY;
      cv_signal(&ns16550->tty_thread_cv);
      res = IF_FILTERED;
    }

    /* transmit register empty? */
    if (iir & IIR_TXRDY) {
      uint8_t byte;
      if (ringbuf_getb(&ns16550->tx_buf, &byte)) {
        out(uart, THR, byte);
      } else {
        /* If we're out of characters and there are characters
         * in the tty's output queue, signal the tty thread to refill. */
        if (ns16550->tty_outq_nonempty) {
          ns16550->tty_ipend |= IIR_TXRDY;
          cv_signal(&ns16550->tty_thread_cv);
        }
        /* Disable TXRDY interrupts - the tty thread will re-enable them
         * after filling tx_buf. */
        clr(uart, IER, IER_ETXRDY);
      }
      res = IF_FILTERED;
    }
  }

  return res;
}

static bool ns16550_getb_lock(ns16550_state_t *ns16550, uint8_t *byte_p) {
  spin_lock(&ns16550->lock);
  bool ret = ringbuf_getb(&ns16550->rx_buf, byte_p);
  spin_unlock(&ns16550->lock);
  return ret;
}

static void ns16550_tty_thread(void *arg) {
  ns16550_state_t *ns16550 = (ns16550_state_t *)arg;
  tty_t *tty = ns16550->tty;
  uint8_t ipend, byte;

  while (true) {
    WITH_SPIN_LOCK (&ns16550->lock) {
      /* Sleep until there's work for us to do. */
      while ((ipend = ns16550->tty_ipend) == 0)
        cv_wait(&ns16550->tty_thread_cv, &ns16550->lock);
      ns16550->tty_ipend = 0;
    }
    WITH_MTX_LOCK (&tty->t_lock) {
      if (ipend & IIR_RXRDY) {
        /* Move characters from rx_buf into the tty's input queue. */
        while (ns16550_getb_lock(ns16550, &byte))
          tty_input(tty, byte);
      }
      if (ipend & IIR_TXRDY) {
        /* Move characters from the tty's output queue to tx_buf. */
        while (true) {
          spin_lock(&ns16550->lock);
          if (ringbuf_full(&ns16550->tx_buf) ||
              !ringbuf_getb(&tty->t_outq, &byte)) {
            /* Enable TXRDY interrupts if there are characters in tx_buf. */
            if (!ringbuf_empty(&ns16550->tx_buf))
              set(ns16550->regs, IER, IER_ETXRDY);
            ns16550->tty_outq_nonempty = !ringbuf_empty(&tty->t_outq);
            spin_unlock(&ns16550->lock);
            break;
          }
          ns16550->tty_outq_nonempty = !ringbuf_empty(&tty->t_outq);
          ringbuf_putb(&ns16550->tx_buf, byte);
          spin_unlock(&ns16550->lock);
        }
      }
    }
  }
}

/*
 * New characters have appeared in the tty's output queue.
 * Notify the tty thread to do the work.
 * Called with `tty->t_lock` held.
 */
static void ns16550_notify_out(tty_t *tty) {
  ns16550_state_t *ns16550 = tty->t_data;

  if (ringbuf_empty(&tty->t_outq))
    return;

  WITH_SPIN_LOCK (&ns16550->lock) {
    ns16550->tty_ipend |= IIR_TXRDY;
    ns16550->tty_outq_nonempty = true;
    cv_signal(&ns16550->tty_thread_cv);
  }
}

static int ns16550_attach(device_t *dev) {
  assert(dev->parent->bus == DEV_BUS_PCI);

  ns16550_state_t *ns16550 = dev->state;

  ns16550->rx_buf.data = kmalloc(M_DEV, UART_BUFSIZE, M_ZERO);
  ns16550->rx_buf.size = UART_BUFSIZE;
  ns16550->tx_buf.data = kmalloc(M_DEV, UART_BUFSIZE, M_ZERO);
  ns16550->tx_buf.size = UART_BUFSIZE;

  spin_init(&ns16550->lock, 0);

  tty_t *tty = tty_alloc();
  tty->t_termios.c_ispeed = 115200;
  tty->t_termios.c_ospeed = 115200;
  tty->t_ops.t_notify_out = ns16550_notify_out;
  tty->t_data = ns16550;
  ns16550->tty = tty;

  cv_init(&ns16550->tty_thread_cv, "NS16550 TTY thread notification");
  thread_t *tty_thread =
    thread_create("NS16550 TTY worker", ns16550_tty_thread, ns16550,
                  prio_ithread(PRIO_ITHRD_QTY - 1));
  sched_add(tty_thread);

  /* TODO Small hack to select COM1 UART */
  ns16550->regs = bus_alloc_resource(
    dev, RT_ISA, 0, IO_COM1, IO_COM1 + IO_COMSIZE - 1, IO_COMSIZE, RF_ACTIVE);
  assert(ns16550->regs != NULL);
  ns16550->intr_handler =
    INTR_HANDLER_INIT(ns16550_intr, NULL, ns16550, "NS16550 UART", 0);
  /* TODO Do not use magic number "4" here! */
  bus_intr_setup(dev, 4, &ns16550->intr_handler);

  /* Setup UART and enable interrupts */
  setup(ns16550->regs);
  out(ns16550->regs, IER, IER_ERXRDY | IER_ETXRDY);

  /* Prepare /dev/uart interface. */
  devfs_makedev(NULL, "uart", &tty_vnodeops, ns16550->tty);

  return 0;
}

static driver_t ns16550_driver = {
  .desc = "NS16550 UART driver",
  .size = sizeof(ns16550_state_t),
  .attach = ns16550_attach,
  .identify = bus_generic_identify,
};

DEVCLASS_ENTRY(pci, ns16550_driver);
