/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */
/*
 * eoslayout: hub offload layout encoder, byte-compatible with the stock
 * eskia.so SkRecordingCanvas / SkLayoutBuilder / SkLayoutPacketizer as driven
 * by the stock displayoffload HAL. See FORMAT.txt for every field and the
 * address it was read from.
 */
#include "eoslayout.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* op header word: size << 8 | 0x80 | type (eskia writes e.g. 0x2888 for a concat) */
#define OP_HDR(type, size)	((uint32_t)(size) << 8 | 0x80u | (type))

enum {
	OP_CONCAT = 8, OP_SAVE = 9, OP_RESTORE = 10, OP_NAMES = 11,
	OP_BITMAP_TEXT = 15, OP_BITMAP_TYPEFACE = 16, OP_BACKGROUND = 17,
	OP_HEADER = 18, OP_BINDING = 19, OP_EXPR_PROPERTY = 20, OP_EXP1 = 21,
	OP_EXP2 = 22, OP_EXP3 = 23, OP_FLOAT = 29, OP_INT64 = 30,
	OP_PROPERTY = 32, OP_LOCALE = 34, OP_TEXT_BINDING = 35, OP_KV = 36,
};

/* SkExpressionType: expr_parse rule actions + byacc tables simulated (re/byacc_sim.py) */
enum {
	EX_ADD = 0, EX_SUB = 1, EX_MUL = 2, EX_DIV = 3, EX_MOD = 4,
	EX_LT = 7, EX_GT = 8, EX_COND = 13, EX_NOT = 14, EX_NEG = 15,
};

#define BT_TEXT_GLYPHS	14	/* SkBindingType of a bitmap-text glyph binding (op 35) */
#define MAX_ITEMS	64

typedef struct {
	uint8_t *d;
	uint32_t len, cap;
} buf;

struct name { char s[16]; uint32_t off; };
struct binding { char name[16]; uint16_t prop; uint16_t type; int vec; };
struct glyphvec { int n; uint16_t slot[32], prop[32]; };
struct expr { uint16_t prop; uint16_t type; char *s; };
struct bitmap { uint32_t id; uint16_t w, h, ct; uint32_t row_bytes; uint8_t *px; };
struct typeface {
	uint32_t id, bitmap_id;
	uint16_t cell_w, cell_h, n;
	float adv[256];
	int packed;
};

struct el_layout {
	buf l[3];
	struct name names[MAX_ITEMS]; int nnames;
	struct binding bind[MAX_ITEMS]; int nbind;
	struct glyphvec vec[MAX_ITEMS]; int nvec;
	struct expr ex[MAX_ITEMS]; int nex;
	struct bitmap bmp[16]; int nbmp;
	struct typeface tf[8]; int ntf;
	uint16_t next_prop;
	uint32_t next_op;
	uint32_t next_bitmap_id, next_typeface_id;
	int finished;
	char err[160];
};

static int fail(el_layout *L, const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(L->err, sizeof(L->err), fmt, ap);
	va_end(ap);
	return -1;
}

const char *el_error(const el_layout *L) { return L->err; }

static void put16(uint8_t *p, uint16_t v) { p[0] = v; p[1] = v >> 8; }
static void put32(uint8_t *p, uint32_t v) { put16(p, v); put16(p + 2, v >> 16); }
static void putf(uint8_t *p, float f) { uint32_t v; memcpy(&v, &f, 4); put32(p, v); }
static void put64(uint8_t *p, uint64_t v) { put32(p, (uint32_t)v); put32(p + 4, v >> 32); }

/* append a zeroed op of `size` bytes (multiple of 4); returns its byte offset in the list */
static int64_t op_add(el_layout *L, int list, uint32_t type, uint32_t size, uint8_t **p)
{
	buf *b = &L->l[list - 1];
	uint32_t off = b->len;

	if (size < 4 || (size & 3) || size >= 1u << 24)
		return fail(L, "bad op size %u", size);
	if (b->len + size > b->cap) {
		uint32_t cap = b->cap ? b->cap : 1024;
		uint8_t *n;

		while (cap < b->len + size)
			cap *= 2;
		n = realloc(b->d, cap);
		if (!n)
			return fail(L, "out of memory");
		b->d = n;
		b->cap = cap;
	}
	memset(b->d + off, 0, size);
	put32(b->d + off, OP_HDR(type, size));
	b->len += size;
	*p = b->d + off;
	return off;
}

/* SkPaint() defaults (eskia 0x2d2f8) -> SkPaintInfo (first 16 bytes); colour bytes R,G,B,A */
static void paint_info(uint8_t *p, uint32_t rgba)
{
	p[0] = rgba >> 24; p[1] = rgba >> 16; p[2] = rgba >> 8; p[3] = rgba;
	putf(p + 4, 1.0f);
	putf(p + 8, 4.0f);
	put32(p + 12, 0x40);
}

el_layout *el_begin(void)
{
	el_layout *L = calloc(1, sizeof(*L));
	uint8_t *p;

	if (!L)
		return NULL;
	L->next_prop = 0x40;		/* stock ESkiaLayoutBuilder +0x80 initial value */
	L->next_bitmap_id = 1;
	L->next_typeface_id = 1;
	/* SkLayoutBuilder ctor: header op 18 at list 1 offset 0 (patched in el_finish) */
	if (op_add(L, 1, OP_HEADER, 12, &p) < 0)
		goto err;
	/* SetNumericLocale default en-US (HAL 0x2198c): op 34 is the first op of list 2 */
	if (op_add(L, 2, OP_LOCALE, 72, &p) < 0)
		goto err;
	put32(p + 4, '.');
	put32(p + 8, ',');
	put16(p + 12, '+');
	put16(p + 20, '-');
	put32(p + 28, 0x10303);
	for (int i = 0; i < 10; i++)
		put32(p + 32 + 4 * i, '0' + i);
	return L;
err:
	el_free(L);
	return NULL;
}

void el_free(el_layout *L)
{
	if (!L)
		return;
	for (int i = 0; i < 3; i++)
		free(L->l[i].d);
	for (int i = 0; i < L->nex; i++)
		free(L->ex[i].s);
	for (int i = 0; i < L->nbmp; i++)
		free(L->bmp[i].px);
	free(L);
}

void el_msgs_free(el_msgs *m)
{
	free(m->msg);
	m->msg = NULL;
	m->count = 0;
}

/* ---- RLE: port of eskia SkRLE::compress (0x37a18), compares kept in bounds ---- */
static int px_eq(const uint8_t *s, uint32_t n, uint32_t a, uint32_t b, uint32_t B)
{
	if (a + B > n || b + B > n)
		return 0;	/* stock memcmp reads past the end here; treat as different */
	return !memcmp(s + a, s + b, B);
}

static void swz(uint8_t *d, const uint8_t *s, uint32_t B)
{
	/* stock HAL passes RGBAToBGRASwizzle (0x25ec6) -> SkOpts::RGBA_to_BGRA */
	if (B == 4) {
		d[0] = s[2]; d[1] = s[1]; d[2] = s[0]; d[3] = s[3];
	} else {
		memcpy(d, s, B);
	}
}

static uint32_t rle_compress(const uint8_t *s, uint32_t n, uint8_t *o, uint32_t cap, uint32_t B)
{
	uint32_t out = 0, i = 0;

	if (n < 2 * B || cap < B + 4 || n % B)
		return 0;
	do {
		uint32_t next, j, cnt;
		int e01, e12;

		if (out + 4 + B > cap)
			break;
		put32(o + out, 0);
		swz(o + out + 4, s + i, B);
		if (i >= n - B) {		/* last pixel: literal of 1 */
			put32(o + out, 1);
			out += 4 + B;
			i = n;
			break;
		}
		e01 = px_eq(s, n, i, i + B, B);
		j = i + B;
		e12 = px_eq(s, n, j, j + B, B);
		next = out + 4 + B;
		if (e01) {			/* run: one pixel, repeated */
			cnt = 1;
			if (e12) {
				int eq;

				do {
					j = i + B;
					if (j >= n || cnt > 0x7ffffffd)
						goto run_done;
					eq = px_eq(s, n, i + 2 * B, i + 3 * B, B);
					cnt++;
					i = j;
				} while (eq);
				j += B;
			}
run_done:
			j += B;
			cnt = (cnt + 1) | 0x80000000u;
		} else {			/* literal: pixels until the next pair repeats */
			cnt = 1;
			if (!e12 && j < n) {
				uint32_t k = 0, off = 0, off4 = 0;

				for (;;) {
					int eq;
					uint32_t t;

					off4 = off;
					if (!(out + 2 * B + 4 + off <= cap && k != 0x7ffffffe))
						break;
					swz(o + out + 4 + B + off, s + j + off, B);
					eq = px_eq(s, n, i + 2 * B + off, i + 3 * B + off, B);
					k++;
					off4 = off + B;
					if (eq)
						break;
					t = i + 2 * B + off;
					off = off4;
					if (t >= n)
						break;
				}
				next += off4;
				j += off4;
				cnt = k + 1;
			}
		}
		put32(o + out, cnt);
		out = next;
		i = j;
	} while (i < n);
	if (i < n)
		return 0;	/* stock: "no room left" */
	return out;
}

int el_background_rgba(el_layout *L, const uint8_t *rgba, int w, int h, int stride)
{
	uint32_t raw = (uint32_t)w * h * 4, z;
	uint8_t *tight, *rle, *p;
	int64_t off;

	if (w != EL_FB_W || h != EL_FB_H)	/* hub: "Background bitmap dimensions do not match frame buffer!" */
		return fail(L, "background must be %dx%d", EL_FB_W, EL_FB_H);
	tight = malloc(raw);
	rle = malloc(raw);
	if (!tight || !rle) {
		free(tight);
		free(rle);
		return fail(L, "out of memory");
	}
	for (int y = 0; y < h; y++)
		memcpy(tight + (size_t)y * w * 4, rgba + (size_t)y * stride, (size_t)w * 4);
	/* stock drawBackgroundBitmap 0x3a7d4: dst capacity = raw size, unit = bpp(RGBA8888) = 4 */
	z = rle_compress(tight, raw, rle, raw, 4);
	free(tight);
	if (!z) {
		free(rle);
		return fail(L, "background does not compress below its raw size");
	}
	off = op_add(L, 1, OP_BACKGROUND, (z + 0x27) & ~3u, &p);
	if (off < 0) {
		free(rle);
		return -1;
	}
	paint_info(p + 4, 0x000000ff);		/* SkPaint() default */
	put32(p + 0x14, z);
	put32(p + 0x18, raw);
	put16(p + 0x1c, h);
	put16(p + 0x1e, w);
	p[0x20] = 4;				/* bytes per pixel: table 0x24690[colortype - 1] */
	memcpy(p + 0x24, rle, z);
	free(rle);
	return 0;
}

int el_glyph_atlas_a8(el_layout *L, int n, int cell_w, int cell_h,
		      const uint8_t *strip, int stride, const float *advances)
{
	struct typeface *t;
	struct bitmap *b;
	uint16_t cw16 = (cell_w + 15) & 0xfff0;	/* HAL AddBitmapTypeface 0x1e570 repack */

	if (L->ntf >= 8 || L->nbmp >= 16)
		return fail(L, "too many atlases");
	if (n < 1 || n > 256 || cell_w < 1 || cell_h < 1 || cell_h > 0xffff ||
	    (uint32_t)n * cw16 > 0xffff)
		return fail(L, "bad atlas geometry");
	b = &L->bmp[L->nbmp];
	b->w = n * cw16;
	b->h = cell_h;
	b->ct = 1;				/* eskia colortype A8 (HAL: AHARDWAREBUFFER R8 0x38 -> 1) */
	b->row_bytes = b->w;
	b->px = calloc((size_t)b->row_bytes, b->h);
	if (!b->px)
		return fail(L, "out of memory");
	for (int g = 0; g < n; g++)
		for (int y = 0; y < cell_h; y++)
			memcpy(b->px + (size_t)y * b->row_bytes + (size_t)g * cw16,
			       strip + (size_t)y * stride + (size_t)g * cell_w, cell_w);
	b->id = L->next_bitmap_id++;
	L->nbmp++;
	t = &L->tf[L->ntf];
	memset(t, 0, sizeof(*t));
	t->id = L->next_typeface_id++;
	t->bitmap_id = b->id;
	t->cell_w = cw16;
	t->cell_h = cell_h;
	t->n = n;
	for (int g = 0; g < n; g++)
		t->adv[g] = advances ? advances[g] : (float)cell_w;
	return L->ntf++;
}

/* SkRecordingCanvas::packBitmapTypeface 0x3a5b4: op 16 into list 2, once per typeface */
static int pack_typeface(el_layout *L, struct typeface *t)
{
	uint8_t *p;

	if (t->packed)
		return 0;
	if (op_add(L, 2, OP_BITMAP_TYPEFACE, 0x14 + 4 * t->n, &p) < 0)
		return -1;
	put32(p + 4, t->id);
	put16(p + 8, t->cell_w);
	put16(p + 10, t->cell_h);
	put32(p + 12, t->n);
	put32(p + 16, t->bitmap_id);
	for (int g = 0; g < t->n; g++)
		putf(p + 20 + 4 * g, t->adv[g]);
	t->packed = 1;
	return 0;
}

static int add_name(el_layout *L, const char *s, uint32_t off)
{
	if (L->nnames >= MAX_ITEMS)
		return fail(L, "too many named ops");
	snprintf(L->names[L->nnames].s, sizeof(L->names[0].s), "%s", s);
	L->names[L->nnames++].off = off;
	return 0;
}

int el_sprite_text(el_layout *L, int typeface, float x, float y, uint32_t rgba,
		   int n, const char *const *glyph_expr, const uint16_t *const_glyphs)
{
	struct typeface *t;
	struct glyphvec *v = NULL;
	char name[16] = "";
	uint8_t *p;
	int64_t off;

	if (L->finished)
		return fail(L, "layout finished");
	if (typeface < 0 || typeface >= L->ntf)
		return fail(L, "bad typeface");
	if (n < 1 || n > 32)
		return fail(L, "1..32 glyphs");
	t = &L->tf[typeface];
	for (int i = 0; i < n; i++) {
		if (!(glyph_expr && glyph_expr[i]))
			continue;
		if (!v) {
			if (L->nvec >= MAX_ITEMS || L->nbind >= MAX_ITEMS)
				return fail(L, "too many bindings");
			v = &L->vec[L->nvec];
			v->n = 0;
		}
		if (L->nex >= MAX_ITEMS || L->next_prop == 0xffff)
			return fail(L, "too many properties");
		L->ex[L->nex].prop = L->next_prop;
		L->ex[L->nex].type = EL_PT_UINT32;	/* glyphIndexBindings are uint32 */
		L->ex[L->nex].s = strdup(glyph_expr[i]);
		if (!L->ex[L->nex].s)
			return fail(L, "out of memory");
		v->slot[v->n] = i;
		v->prop[v->n] = L->next_prop++;
		v->n++;
		L->nex++;
	}
	/* TranslationGroup with constant offsets (HAL 0x245e8): save, translate, child, restore */
	if (op_add(L, 1, OP_SAVE, 4, &p) < 0)
		return -1;
	if (op_add(L, 1, OP_CONCAT, 40, &p) < 0)
		return -1;
	putf(p + 4, 1.0f);	/* SkMatrix {sx, kx, tx, ky, sy, ty, p0, p1, p2} */
	putf(p + 12, x);
	putf(p + 20, 1.0f);
	putf(p + 24, y);
	putf(p + 36, 1.0f);
	if (v) {
		/* GetNextOpId (HAL 0x21ed8): "op" + pre-incremented counter */
		snprintf(name, sizeof(name), "op%u", ++L->next_op);
		snprintf(L->bind[L->nbind].name, sizeof(L->bind[0].name), "%s", name);
		L->bind[L->nbind].type = BT_TEXT_GLYPHS;
		L->bind[L->nbind].vec = L->nvec;
		L->bind[L->nbind].prop = L->nvec;
		L->nbind++;
		L->nvec++;
	}
	if (pack_typeface(L, t) < 0)
		return -1;
	/* SkRecordingCanvas::drawBitmapText 0x3a708, at (0,0) inside the group */
	off = op_add(L, 1, OP_BITMAP_TEXT, (2 * n + 0x37) & ~3u, &p);
	if (off < 0)
		return -1;
	paint_info(p + 4, rgba);
	put32(p + 0x14, t->id);
	putf(p + 0x18, 0.0f);
	putf(p + 0x1c, 0.0f);
	put32(p + 0x20, n);
	for (int i = 0; i < n; i++)
		put16(p + 0x34 + 2 * i, (glyph_expr && glyph_expr[i]) ? 0 :
					(const_glyphs ? const_glyphs[i] : 0));
	if (v && add_name(L, name, (uint32_t)off) < 0)
		return -1;
	if (op_add(L, 1, OP_RESTORE, 4, &p) < 0)
		return -1;
	return 0;
}

int el_kv(el_layout *L, const char *key, const char *value)
{
	size_t kl = strlen(key), vl = strlen(value);
	uint8_t *p;

	if (kl + vl == 0 || kl + vl > 0x3ff)	/* stock writeKeyValuePair bound */
		return fail(L, "kv size");
	if (op_add(L, 2, OP_KV, (kl + vl + 13) & ~3u, &p) < 0)
		return -1;
	put16(p + 4, kl);
	put16(p + 6, vl);
	memcpy(p + 8, key, kl);
	memcpy(p + 9 + kl, value, vl);
	return 0;
}

/* ---- expressions: recursive descent emitting nodes in the order the stock
 * byacc parser reduces them (operands first). A node reference is the byte
 * offset of the node op inside list 2 (ParserContext: *ref = SkOpList+0xc). ---- */
struct ex_ctx { el_layout *L; const char *s; };

static void ex_ws(struct ex_ctx *c) { while (*c->s == ' ' || *c->s == '\t') c->s++; }

static int64_t ex_cond(struct ex_ctx *c);

static int64_t node1(struct ex_ctx *c, uint32_t type, uint32_t a)
{
	uint8_t *p;
	int64_t o = op_add(c->L, 2, OP_EXP1, 16, &p);

	if (o >= 0) {
		put32(p + 4, type);
		put32(p + 8, a);
	}
	return o;
}

static int64_t node2(struct ex_ctx *c, uint32_t type, uint32_t a, uint32_t b)
{
	uint8_t *p;
	int64_t o = op_add(c->L, 2, OP_EXP2, 24, &p);

	if (o >= 0) {
		put32(p + 4, type);
		put32(p + 8, a);
		put32(p + 16, b);
	}
	return o;
}

static int64_t ex_primary(struct ex_ctx *c)
{
	uint8_t *p;
	int64_t o;

	ex_ws(c);
	if (*c->s == '(') {
		c->s++;
		o = ex_cond(c);
		ex_ws(c);
		if (o < 0)
			return o;
		if (*c->s != ')')
			return fail(c->L, "expected )");
		c->s++;
		return o;
	}
	if (*c->s == '{') {
		char *e;
		unsigned long id = strtoul(c->s + 1, &e, 10);

		if (e == c->s + 1 || *e != '}' || id > 0xffff)
			return fail(c->L, "bad property reference");
		c->s = e + 1;
		o = op_add(c->L, 2, OP_PROPERTY, 8, &p);
		if (o >= 0)
			put16(p + 4, id);
		return o;
	}
	if ((*c->s >= '0' && *c->s <= '9') || *c->s == '.') {
		const char *q = c->s;
		int isf = 0;

		while ((*q >= '0' && *q <= '9') || *q == '.') {
			if (*q == '.')
				isf = 1;
			q++;
		}
		if (isf) {
			float f = strtof(c->s, NULL);

			o = op_add(c->L, 2, OP_FLOAT, 8, &p);
			if (o >= 0)
				putf(p + 4, f);
		} else {
			long long v = strtoll(c->s, NULL, 10);

			o = op_add(c->L, 2, OP_INT64, 12, &p);
			if (o >= 0)
				put64(p + 4, (uint64_t)v);
		}
		c->s = q;
		return o;
	}
	return fail(c->L, "unexpected '%c' in expression", *c->s ? *c->s : '?');
}

static int64_t ex_unary(struct ex_ctx *c)
{
	int64_t a;

	ex_ws(c);
	if (*c->s == '-' || *c->s == '!') {
		uint32_t t = *c->s == '-' ? EX_NEG : EX_NOT;

		c->s++;
		a = ex_unary(c);
		return a < 0 ? a : node1(c, t, (uint32_t)a);
	}
	return ex_primary(c);
}

static int64_t ex_mul(struct ex_ctx *c)
{
	int64_t a = ex_unary(c), b;

	for (;;) {
		uint32_t t;

		if (a < 0)
			return a;
		ex_ws(c);
		if (*c->s == '*')
			t = EX_MUL;
		else if (*c->s == '/')
			t = EX_DIV;
		else if (*c->s == '%')
			t = EX_MOD;
		else
			return a;
		c->s++;
		b = ex_unary(c);
		if (b < 0)
			return b;
		a = node2(c, t, (uint32_t)a, (uint32_t)b);
	}
}

static int64_t ex_add(struct ex_ctx *c)
{
	int64_t a = ex_mul(c), b;

	for (;;) {
		uint32_t t;

		if (a < 0)
			return a;
		ex_ws(c);
		if (*c->s == '+')
			t = EX_ADD;
		else if (*c->s == '-')
			t = EX_SUB;
		else
			return a;
		c->s++;
		b = ex_mul(c);
		if (b < 0)
			return b;
		a = node2(c, t, (uint32_t)a, (uint32_t)b);
	}
}

static int64_t ex_cmp(struct ex_ctx *c)
{
	int64_t a = ex_add(c), b;

	for (;;) {
		uint32_t t;

		if (a < 0)
			return a;
		ex_ws(c);
		/* == != <= >= && || exist (tokens 0x105..0x10a, types 5,6,9..12) but
		 * which is which is not resolved: refused */
		if ((c->s[0] == '<' || c->s[0] == '>') && c->s[1] == '=')
			return fail(c->L, "<= and >= are not supported");
		if (c->s[0] == '<')
			t = EX_LT;
		else if (c->s[0] == '>')
			t = EX_GT;
		else
			return a;
		c->s++;
		b = ex_add(c);
		if (b < 0)
			return b;
		a = node2(c, t, (uint32_t)a, (uint32_t)b);
	}
}

static int64_t ex_cond(struct ex_ctx *c)
{
	int64_t a = ex_cmp(c), b, d, o;
	uint8_t *p;

	if (a < 0)
		return a;
	ex_ws(c);
	if (*c->s != '?')
		return a;
	c->s++;
	b = ex_cond(c);
	if (b < 0)
		return b;
	ex_ws(c);
	if (*c->s != ':')
		return fail(c->L, "expected :");
	c->s++;
	d = ex_cond(c);
	if (d < 0)
		return d;
	o = op_add(c->L, 2, OP_EXP3, 32, &p);	/* newExp3 0x3af08 */
	if (o >= 0) {
		put32(p + 4, EX_COND);
		put32(p + 8, (uint32_t)a);
		put32(p + 16, (uint32_t)b);
		put32(p + 24, (uint32_t)d);
	}
	return o;
}

static int write_expr(el_layout *L, const struct expr *e)
{
	struct ex_ctx c = { L, e->s };
	uint8_t *p;
	int64_t root;

	root = ex_cond(&c);
	if (root < 0)
		return -1;
	ex_ws(&c);
	if (*c.s)
		return fail(L, "trailing text in expression %s", e->s);
	/* SkLayoutBuilder::writeExpressionProperty 0x38ed4: op 20 */
	if (op_add(L, 2, OP_EXPR_PROPERTY, 16, &p) < 0)
		return -1;
	put16(p + 4, e->prop);
	put16(p + 6, e->type);
	put32(p + 8, (uint32_t)root);
	return 0;
}

static int cmp_name(const void *a, const void *b)
{
	return strcmp(((const struct name *)a)->s, ((const struct name *)b)->s);
}

/* ---- SkLayoutPacketizer 0x383a8: 253-byte packets, the HAL prefixes 01 02 ---- */
#define PKT_CAP 253

static el_msg *new_msg(el_msgs *m, int *cap)
{
	if (m->count == *cap) {
		int c = *cap ? *cap * 2 : 64;
		el_msg *n = realloc(m->msg, (size_t)c * sizeof(*n));

		if (!n)
			return NULL;
		m->msg = n;
		*cap = c;
	}
	memset(&m->msg[m->count], 0, sizeof(el_msg));
	m->msg[m->count].b[0] = 1;	/* version */
	m->msg[m->count].b[1] = 2;	/* RenderService command 2: one layout packet */
	return &m->msg[m->count++];
}

static int packetize(el_layout *L, el_msgs *m)
{
	int cap = 0;
	el_msg *x;

	memset(m, 0, sizeof(*m));
	/* op lists 1..3, 10-byte header + up to 243 bytes each; empty lists send nothing */
	for (int li = 0; li < 3; li++) {
		buf *b = &L->l[li];

		m->oplist_size[li] = b->len;
		for (uint32_t off = 0; off < b->len;) {
			uint32_t n = b->len - off;

			if (n > PKT_CAP - 10)
				n = PKT_CAP - 10;
			if (!(x = new_msg(m, &cap)))
				return fail(L, "out of memory");
			x->b[2] = 0;
			x->b[3] = 1;
			put32(x->b + 4, b->len);
			x->b[8] = li + 1;
			memcpy(x->b + 12, b->d + off, n);
			x->len = 2 + 10 + n;
			off += n;
		}
	}
	/* bitmaps: 16-byte header {id, row_bytes, w, h, colorinfo, 0} + rows as one
	 * stream; after each bitmap the stock iterator emits one empty bitmap packet */
	for (int bi = 0; bi < L->nbmp; bi++) {
		struct bitmap *bm = &L->bmp[bi];
		uint8_t hdr[16] = { 0 };
		uint32_t hs = 0, ps = 0, total = bm->row_bytes * bm->h;

		put32(hdr, bm->id);
		put32(hdr + 4, bm->row_bytes);
		put16(hdr + 8, bm->w);
		put16(hdr + 10, bm->h);
		put16(hdr + 12, bm->ct);
		m->bitmap_bytes += total;
		for (;;) {
			uint32_t room = PKT_CAP - 6, n = 0;

			if (!(x = new_msg(m, &cap)))
				return fail(L, "out of memory");
			x->b[2] = 0;
			x->b[3] = 2;
			if (hs < 16) {
				uint32_t k = 16 - hs < room ? 16 - hs : room;

				memcpy(x->b + 8, hdr + hs, k);
				hs += k;
				n += k;
				room -= k;
			}
			if (room && ps < total) {
				uint32_t k = total - ps < room ? total - ps : room;

				memcpy(x->b + 8 + n, bm->px + ps, k);
				ps += k;
				n += k;
			}
			put32(x->b + 4, n);
			x->len = 2 + 6 + n;
			if (n == 0)	/* the iterator-advance packet */
				break;
		}
	}
	if (!(x = new_msg(m, &cap)))
		return fail(L, "out of memory");
	x->b[2] = 0;
	x->b[3] = 3;		/* finished */
	x->len = 4;
	/* HAL SendLayout 0x1b9c4: RenderSync after every 40th packet */
	for (int i = 0; i < m->count; i++)
		m->msg[i].sync_after = ((i + 1) % 40) == 0;
	return 0;
}

int el_finish(el_layout *L, el_msgs *out)
{
	uint8_t *p, *q;
	int64_t off;
	uint32_t sz = 4;

	if (L->finished)
		return fail(L, "already finished");
	/* BuildExpressions (HAL 0x26a40): nodes + op 20 per generated property */
	for (int i = 0; i < L->nex; i++)
		if (write_expr(L, &L->ex[i]) < 0)
			return -1;
	/* SkLayoutBuilder::finish 0x38a3e: bindings into list 3 (ours: no type 6) */
	for (int i = 0; i < L->nbind; i++) {
		struct binding *bd = &L->bind[i];
		int k;

		for (k = 0; k < L->nnames && strcmp(L->names[k].s, bd->name); k++)
			;
		if (k == L->nnames)
			continue;	/* stock: an unresolved id drops the binding */
		if (bd->type == BT_TEXT_GLYPHS) {
			struct glyphvec *v = &L->vec[bd->vec];

			if (op_add(L, 3, OP_TEXT_BINDING, 4 * v->n + 12, &p) < 0)
				return -1;
			put32(p + 4, v->n);
			put32(p + 8, L->names[k].off);
			for (int j = 0; j < v->n; j++) {
				put16(p + 12 + 2 * j, v->slot[j]);
				put16(p + 12 + 2 * v->n + 2 * j, v->prop[j]);
			}
		} else {
			if (op_add(L, 3, OP_BINDING, 12, &p) < 0)
				return -1;
			put32(p + 4, (uint32_t)bd->type << 16 | bd->prop);
			put32(p + 8, L->names[k].off);
		}
	}
	/* SkRecordingCanvas::build 0x3a2f8: named-op table (std::map order) ends list 1 */
	qsort(L->names, L->nnames, sizeof(L->names[0]), cmp_name);
	for (int i = 0; i < L->nnames; i++)
		sz += (strlen(L->names[i].s) + 0xb) & ~3u;
	off = op_add(L, 1, OP_NAMES, sz, &p);
	if (off < 0)
		return -1;
	q = p + 4;
	for (int i = 0; i < L->nnames; i++) {
		uint32_t n = strlen(L->names[i].s);

		put32(q, n);
		put32(q + 4, L->names[i].off);
		memcpy(q + 8, L->names[i].s, n);
		q += (n + 0xb) & ~3u;
	}
	/* header op 18: +4 = offset of the name table, +8 = number of names */
	put32(L->l[0].d + 4, (uint32_t)off);
	put32(L->l[0].d + 8, L->nnames);
	L->finished = 1;
	return packetize(L, out);
}

const uint8_t *el_oplist(const el_layout *L, int list, uint32_t *len)
{
	if (list < 1 || list > 3)
		return NULL;
	*len = L->l[list - 1].len;
	return L->l[list - 1].d;
}

int el_msg_render_reset(uint8_t *b) { b[0] = 1; b[1] = 3; return 2; }
int el_msg_render_stats(uint8_t *b) { b[0] = 1; b[1] = 6; return 2; }
int el_msg_render_sync(uint8_t *b) { b[0] = 1; b[1] = 7; return 2; }

int el_msg_sync_time(uint8_t *b, int64_t unix_minus_boot_ms, uint32_t local_ms_of_day)
{
	b[0] = 1;
	b[1] = 1;
	put64(b + 2, (uint64_t)unix_minus_boot_ms);
	put32(b + 10, local_ms_of_day);
	return 14;
}
