#ifndef _SYS_RINGBUF_H_
#define _SYS_RINGBUF_H_

#include <sys/cdefs.h>
#include <sys/mimiker.h>

typedef struct uio uio_t;

typedef struct ringbuf {
  size_t head;   /*!< producing data moves head forward */
  size_t tail;   /*!< consuming data moves tail forward */
  size_t count;  /*!< number of bytes currently stored in the buffer */
  size_t size;   /*!< total size of the buffer */
  uint8_t *data; /*!< buffer that stores data */
} ringbuf_t;

static inline bool ringbuf_empty(ringbuf_t *buf) {
  return buf->count == 0;
}

static inline bool ringbuf_full(ringbuf_t *buf) {
  return buf->count == buf->size;
}

static inline void consume(ringbuf_t *buf, unsigned bytes) {
  /* assert(buf->count >= bytes); */
  /* assert(buf->tail + bytes <= buf->size); */
  buf->count -= bytes;
  buf->tail += bytes;
  if (buf->tail == buf->size)
    buf->tail = 0;
}

static inline void produce(ringbuf_t *buf, unsigned bytes) {
  /* assert(buf->count + bytes <= buf->size); */
  /* assert(buf->head + bytes <= buf->size); */
  buf->count += bytes;
  buf->head += bytes;
  if (buf->head == buf->size)
    buf->head = 0;
}

static inline bool ringbuf_putb(ringbuf_t *buf, uint8_t byte) {
  if (buf->count == buf->size)
    return false;
  buf->data[buf->head] = byte;
  produce(buf, 1);
  return true;
}

static inline bool ringbuf_getb(ringbuf_t *buf, uint8_t *byte_p) {
  if (buf->count == 0)
    return false;
  *byte_p = buf->data[buf->tail];
  consume(buf, 1);
  return true;
}

void ringbuf_init(ringbuf_t *rb, void *buf, size_t size);
int ringbuf_read(ringbuf_t *buf, uio_t *uio);
int ringbuf_write(ringbuf_t *buf, uio_t *uio);
void ringbuf_reset(ringbuf_t *buf);

#endif /* !_SYS_RINGBUF_H_ */
