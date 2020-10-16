#include <sys/mimiker.h>
#include <sys/ringbuf.h>
#include <sys/uio.h>

void ringbuf_init(ringbuf_t *rb, void *buf, size_t size) {
  rb->head = 0;
  rb->tail = 0;
  rb->count = 0;
  rb->size = size;
  rb->data = buf;
}

int ringbuf_read(ringbuf_t *buf, uio_t *uio) {
  assert(uio->uio_op == UIO_READ);
  /* repeat when used space is split into two parts */
  while (uio->uio_resid > 0 && !ringbuf_empty(buf)) {
    /* used space is either [tail, head) or [tail, size) */
    size_t size =
      (buf->tail < buf->head) ? buf->head - buf->tail : buf->size - buf->tail;
    if (size > uio->uio_resid)
      size = uio->uio_resid;
    int res = uiomove((char *)buf->data + buf->tail, size, uio);
    if (res)
      return res;
    consume(buf, size);
  }
  return 0;
}

int ringbuf_write(ringbuf_t *buf, uio_t *uio) {
  assert(uio->uio_op == UIO_WRITE);
  /* repeat when free space is split into two parts */
  while (uio->uio_resid > 0 && !ringbuf_full(buf)) {
    /* free space is either [head, tail) or [head, size) */
    size_t size =
      (buf->head < buf->tail) ? buf->tail - buf->head : buf->size - buf->head;
    if (size > uio->uio_resid)
      size = uio->uio_resid;
    int res = uiomove((char *)buf->data + buf->head, size, uio);
    if (res)
      return res;
    produce(buf, size);
  }
  return 0;
}

void ringbuf_reset(ringbuf_t *buf) {
  ringbuf_init(buf, buf->data, buf->size);
}
