/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * eoslayout: encoder for Pixel Watch 2 sensor-hub (MCU) offload layouts, the
 * eSkia op-list format the stock displayoffload HAL
 * (vendor.google_clockwork.displayoffload@2.0-service.1p + vendor/lib/eskia.so)
 * sends on /dev/nanohub_render (nanohub channel 18). Byte layout and evidence:
 * FORMAT.txt next to this file. C99, libc only.
 *
 * Usage:
 *   el_layout *L = el_begin();
 *   el_background_rgba(L, rgba, 384, 384, 384 * 4);
 *   int tf = el_glyph_atlas_a8(L, 11, 48, 80, strip, 11 * 48, advances);
 *   const char *e[5] = { "({0}/10)", "({0}%10)", NULL, "({1}/10)", "({1}%10)" };
 *   uint16_t c[5] = { 0, 0, 10, 0, 0 };          // slot 2 = constant glyph 10
 *   el_sprite_text(L, tf, 74, 152, 0xffffffff, 5, e, c);
 *   el_msgs m; el_finish(L, &m);  // m.msg[i] = one write() each, in order
 *   ... send el_msg_render_reset() first, then m.msg[]; after every message
 *   with sync_after set, send el_msg_render_sync() and wait for {07 00000000}.
 */
#ifndef EOSLAYOUT_H
#define EOSLAYOUT_H

#include <stddef.h>
#include <stdint.h>

#define EL_MSG_MAX	255	/* nanohub message limit (uint8 length) */
#define EL_FB_W		384
#define EL_FB_H		384

/* builtin metric properties ({N} in expressions), stock HAL GetExpressionForMetric */
#define EL_PROP_HOUR24	0	/* 0..23 */
#define EL_PROP_MINUTE	1
#define EL_PROP_SECOND	2

/* eSkia PropertyType (stock HAL table 0x18248: BindingPtr type -> PropertyType) */
#define EL_PT_UINT32	3
#define EL_PT_UINT64	4
#define EL_PT_INT32	7
#define EL_PT_INT64	8
#define EL_PT_FLOAT	9

typedef struct {
	uint8_t len;
	uint8_t sync_after;	/* stock: RenderSync after every 40th layout packet */
	uint8_t b[EL_MSG_MAX];
} el_msg;

typedef struct {
	el_msg *msg;
	int count;
	/* sizes, for logs and limits */
	uint32_t oplist_size[3];
	uint32_t bitmap_bytes;
} el_msgs;

typedef struct el_layout el_layout;

el_layout *el_begin(void);
void el_free(el_layout *L);
void el_msgs_free(el_msgs *m);
const char *el_error(const el_layout *L);

/* Full-screen opaque background (op 17), RGBA8888 bytes R,G,B,A; must be 384x384. */
int el_background_rgba(el_layout *L, const uint8_t *rgba, int w, int h, int stride);

/*
 * Glyph sprite atlas (op 16 + one A8 bitmap): n glyphs side by side in one
 * row, each cell_w x cell_h, coverage 0..255, row stride in bytes. Cells are
 * repacked to a width that is a multiple of 16 like the stock HAL.
 * advances[i] = pen advance of glyph i in pixels (NULL: cell_w).
 * Returns a typeface handle (>= 0) or -1.
 */
int el_glyph_atlas_a8(el_layout *L, int n, int cell_w, int cell_h,
		      const uint8_t *strip, int stride, const float *advances);

/*
 * Sprite string (stock SpriteStringDrawable): n glyph slots drawn from the
 * atlas inside a translation group at (x, y) (top-left of the first cell),
 * tinted with rgba (0xRRGGBBAA). glyph_expr[i] = eSkia expression giving the
 * glyph index ({N} = property N, e.g. "({1}%10)"), or NULL for the constant
 * const_glyphs[i]. Returns 0 or -1.
 */
int el_sprite_text(el_layout *L, int typeface, float x, float y, uint32_t rgba,
		   int n, const char *const *glyph_expr, const uint16_t *const_glyphs);

/*
 * The same with the translation bound to expressions (the stock TranslationGroup with a
 * bound offset): x_expr / y_expr (NULL: the constant x / y) give the top-left of the
 * first cell as a float, e.g. "(" EL_EXPR_HOUR12 " < 10 ? 120.0 : 96.0)".
 */
int el_sprite_text_at(el_layout *L, int typeface, float x, float y, const char *x_expr,
		      const char *y_expr, uint32_t rgba, int n, const char *const *glyph_expr,
		      const uint16_t *const_glyphs);

/* Layout annotation (op 36), e.g. "render_trigger.min_data_period.sec" "60". */
int el_kv(el_layout *L, const char *key, const char *value);

/* Build the op lists and the ch18 messages (01 02 + one layout packet each). */
int el_finish(el_layout *L, el_msgs *out);

/* Raw access after el_finish (tests): op list 1..3 */
const uint8_t *el_oplist(const el_layout *L, int list, uint32_t *len);

/* Other ch18 commands (byte 0 = version 1). Return the message length. */
int el_msg_render_reset(uint8_t *b);	/* 01 03 */
int el_msg_render_stats(uint8_t *b);	/* 01 06, reply 17 bytes */
int el_msg_render_sync(uint8_t *b);	/* 01 07, reply {07, u32 0 = ok} */
/* 01 01 + i64 unix_ms - boottime_ms (stock: realtime - elapsedRealtime) + u32 local ms since midnight */
int el_msg_sync_time(uint8_t *b, int64_t unix_minus_boot_ms, uint32_t local_ms_of_day);

/* Stock time expressions (HAL map, GetExpressionForMetric) */
#define EL_EXPR_HOUR24_D1	"({0}/10)"
#define EL_EXPR_HOUR24_D2	"({0}%10)"
#define EL_EXPR_HOUR12_D1	"((({0} + 11)%12 + 1)/10)"
#define EL_EXPR_HOUR12_D2	"((({0} + 11)%12 + 1)%10)"
#define EL_EXPR_MIN_D1		"({1}/10)"
#define EL_EXPR_MIN_D2		"({1}%10)"
/* the hour of a 12 h clock, 1..12 (the inner part of the stock hour12 expressions) */
#define EL_EXPR_HOUR12		"(({0} + 11)%12 + 1)"

#endif
