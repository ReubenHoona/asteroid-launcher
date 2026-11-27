/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

/*
 * The hub layout encoder's additions of R5 (src/eoslayout.c):
 *  - K-03: the health metrics of the stock HAL's map as properties ({3} heart rate, {5} steps, ...): a
 *    glyph expression on them is a property node with that id;
 *  - A-05: expression functions (cos, sin, PI, floor, ceil, toIntS32: eskia's table, op 24 + the
 *    argument count, the id, the arguments' node references written before the call) and rotation
 *    groups (stock RotationGroup: save, one named concat op, its elements 0, 1, 2, 4, 3, 5 bound to
 *    float expressions of the angle, restore; groups nest; one left open fails el_finish);
 *  - the errors: an unknown function, a wrong argument count, a group end without a group.
 * With EL_PROBE_DIR set it also writes the two probe layouts of the on-watch check
 * (wearimpl/pkg/R5-aod/TEST.txt): probe-hands.hex (two hands turning with the time) and
 * probe-metrics.hex (heart rate and steps as digits; a dash where the hub has no value); the
 * host model (layoutmodel.py) renders them. No Qt.
 */

extern "C" {
#include "eoslayout.h"
}

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

struct Op { uint32_t off, type, size; const uint8_t *p; };

static uint32_t u32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t u16(const uint8_t *p) { return p[0] | p[1] << 8; }

static std::vector<Op> ops(const el_layout *L, int list)
{
	uint32_t len = 0;
	const uint8_t *d = el_oplist(L, list, &len);
	std::vector<Op> out;
	for (uint32_t o = 0; d && o + 4 <= len;) {
		uint32_t h = u32(d + o);
		uint32_t size = h >> 8;
		if (size < 4)
			break;
		out.push_back({ o, h & 0x3f, size, d + o });
		o += size;
	}
	return out;
}

// an A8 atlas of n cells of cw x ch, cell i drawn by f(i, x, y)
template <typename F>
static int atlas(el_layout *L, int n, int cw, int ch, F f)
{
	std::vector<uint8_t> s((size_t)n * cw * ch);
	for (int i = 0; i < n; i++)
		for (int y = 0; y < ch; y++)
			for (int x = 0; x < cw; x++)
				s[(size_t)y * n * cw + i * cw + x] = f(i, x, y);
	return el_glyph_atlas_a8(L, n, cw, ch, s.data(), n * cw, nullptr);
}

static el_layout *withBackground()
{
	el_layout *L = el_begin();
	std::vector<uint8_t> bg(EL_FB_W * EL_FB_H * 4, 0);
	for (size_t i = 3; i < bg.size(); i += 4)
		bg[i] = 255;
	el_background_rgba(L, bg.data(), EL_FB_W, EL_FB_H, EL_FB_W * 4);
	return L;
}

static void functions()
{
	el_layout *L = withBackground();
	int tf = atlas(L, 2, 16, 16, [](int i, int, int) { return i ? 255 : 0; });
	const char *e[1] = { "toIntS32(floor(cos(PI()*2.0)+0.5))" };
	CHECK(el_sprite_text(L, tf, 10, 10, 0xffffffff, 1, e, nullptr) == 0);
	el_msgs m;
	CHECK(el_finish(L, &m) == 0);
	int pi = 0, cos1 = 0, floor1 = 0, toint = 0, bad = 0;
	std::vector<Op> l2 = ops(L, 2);
	for (const Op &o : l2) {
		if (o.type >= 24 && o.type <= 28) {
			const uint32_t n = o.type - 24, id = u32(o.p + 4);
			if (o.size != 8 + 8 * n)
				bad++;
			for (uint32_t k = 0; k < n; k++)
				if (u32(o.p + 8 + 8 * k) >= o.off || u32(o.p + 12 + 8 * k) != 0)
					bad++;
			pi += id == 3 && n == 0;
			cos1 += id == 1 && n == 1;
			floor1 += id == 15 && n == 1;
			toint += id == 19 && n == 1;
		}
	}
	CHECK(pi == 1 && cos1 == 1 && floor1 == 1 && toint == 1);
	CHECK(bad == 0);
	el_msgs_free(&m);
	el_free(L);

	const char *errs[] = { "nofunc(1)", "cos(1.0, 2.0)", "PI(1)", "sin 1.0", "cos(1.0" };
	for (const char *x : errs) {
		el_layout *B = withBackground();
		int t = atlas(B, 2, 16, 16, [](int, int, int) { return 0; });
		const char *ee[1] = { x };
		el_sprite_text(B, t, 0, 0, 0xffffffff, 1, ee, nullptr);
		el_msgs mm;
		CHECK(el_finish(B, &mm) != 0);
		CHECK(std::strlen(el_error(B)) > 0);
		el_free(B);
	}
}

static void rotation()
{
	el_layout *L = withBackground();
	int tf = atlas(L, 1, 16, 100, [](int, int x, int) { return x >= 6 && x < 10 ? 255 : 0; });
	const uint16_t g[1] = { 0 };
	CHECK(el_rotation_begin(L, 192, 192, EL_EXPR_MINUTE_ONLY_DEG) == 0);
	CHECK(el_sprite_text(L, tf, 184, 92, 0xffffffff, 1, nullptr, g) == 0);
	CHECK(el_group_end(L) == 0);
	CHECK(el_group_end(L) != 0);       // none open
	el_msgs m;
	CHECK(el_finish(L, &m) == 0);
	std::vector<Op> l1 = ops(L, 1), l2 = ops(L, 2), l3 = ops(L, 3);
	// header, background, save, concat (the group), save, concat, text, restore (the sprite), restore, names
	std::vector<uint32_t> types;
	for (const Op &o : l1)
		types.push_back(o.type);
	const std::vector<uint32_t> want = { 18, 17, 9, 8, 9, 8, 15, 10, 10, 11 };
	CHECK(types == want);
	const uint32_t concat = l1[3].off;
	std::vector<uint32_t> elems;
	std::vector<uint16_t> props;
	for (const Op &o : l3)
		if (o.type == 19 && u32(o.p + 8) == concat) {
			elems.push_back(u32(o.p + 4) >> 16);
			props.push_back(u32(o.p + 4) & 0xffff);
		}
	const std::vector<uint32_t> order = { 0, 1, 2, 4, 3, 5 };
	CHECK(elems == order);
	int floats = 0, cos = 0, sin = 0;
	for (const Op &o : l2) {
		if (o.type == 20)
			for (uint16_t p : props)
				floats += u16(o.p + 4) == p && u16(o.p + 6) == EL_PT_FLOAT;
		if (o.type == 25)
			(u32(o.p + 4) == 1 ? cos : sin) += u32(o.p + 4) == 1 || u32(o.p + 4) == 2;
	}
	CHECK(floats == 6);
	CHECK(cos == 4 && sin == 4);       // elements 0, 2, 4, 5 have a cos; 1, 2, 3, 5 a sin
	// the concat's constant matrix is the identity (angle 0 until the hub evaluates)
	float f[9];
	std::memcpy(f, l1[3].p + 4, sizeof(f));
	CHECK(f[0] == 1.0f && f[4] == 1.0f && f[8] == 1.0f && f[1] == 0.0f && f[2] == 0.0f);
	el_msgs_free(&m);
	el_free(L);

	// a group left open fails; a constant (null) angle has no bindings; groups nest
	el_layout *O = withBackground();
	CHECK(el_rotation_begin(O, 0, 0, nullptr) == 0);
	CHECK(el_rotation_begin(O, 10, 10, "45.0") == 0);
	CHECK(el_group_end(O) == 0);
	el_msgs mo;
	CHECK(el_finish(O, &mo) != 0);
	el_free(O);
	el_layout *C = withBackground();
	CHECK(el_rotation_begin(C, 0, 0, nullptr) == 0);
	CHECK(el_group_end(C) == 0);
	el_msgs mc;
	CHECK(el_finish(C, &mc) == 0);
	CHECK(ops(C, 3).empty());
	el_msgs_free(&mc);
	el_free(C);
}

static void metrics()
{
	el_layout *L = withBackground();
	int tf = atlas(L, 12, 16, 16, [](int, int, int) { return 255; });
	const char *e[2] = { "((" "{5}" "/1000)%10 + 1)", "({3}%10 + 1)" };
	CHECK(el_sprite_text(L, tf, 0, 0, 0xffffffff, 2, e, nullptr) == 0);
	el_msgs m;
	CHECK(el_finish(L, &m) == 0);
	int steps = 0, hr = 0;
	for (const Op &o : ops(L, 2))
		if (o.type == 32) {
			steps += u16(o.p + 4) == EL_PROP_DAY_STEPS;
			hr += u16(o.p + 4) == EL_PROP_HR_BPM;
		}
	CHECK(steps == 1 && hr == 1);
	CHECK(EL_PROP_DAY_STEPS == 5 && EL_PROP_HR_BPM == 3 && EL_PROP_DAY_FLOORS == 30);
	el_msgs_free(&m);
	el_free(L);
}

static bool writeHex(el_layout *L, const std::string &path)
{
	el_msgs m;
	if (el_finish(L, &m))
		return false;
	FILE *f = fopen(path.c_str(), "w");
	if (!f)
		return false;
	fprintf(f, "# R5 probe layout\n0103\n");
	for (int i = 0; i < m.count; i++) {
		for (int j = 0; j < m.msg[i].len; j++)
			fprintf(f, "%02x", m.msg[i].b[j]);
		fprintf(f, "\n");
		if (m.msg[i].sync_after)
			fprintf(f, "# sync\n");
	}
	fclose(f);
	el_msgs_free(&m);
	return true;
}

// 5 x 7 segment digits on a 16 x 24 cell: cell 0 a dash, 1..10 the digits 0..9, 11 blank
static uint8_t digitPixel(int i, int x, int y)
{
	static const uint8_t seg[10] = { 0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f };
	if (i == 11)
		return 0;
	const uint8_t s = i == 0 ? 0x40 : seg[i - 1];
	const bool h = x >= 3 && x < 13, v1 = x >= 2 && x < 5, v2 = x >= 11 && x < 14;
	if ((s & 0x01) && h && y >= 1 && y < 4) return 255;          // a
	if ((s & 0x02) && v2 && y >= 2 && y < 12) return 255;        // b
	if ((s & 0x04) && v2 && y >= 12 && y < 22) return 255;       // c
	if ((s & 0x08) && h && y >= 20 && y < 23) return 255;        // d
	if ((s & 0x10) && v1 && y >= 12 && y < 22) return 255;       // e
	if ((s & 0x20) && v1 && y >= 2 && y < 12) return 255;        // f
	if ((s & 0x40) && h && y >= 10 && y < 14) return 255;        // g
	return 0;
}

static void probes(const char *dir)
{
	// two hands: the hour (80 px, grey) and the minute (130 px, white) from the centre, turning with the time
	el_layout *H = withBackground();
	// cell 0 the minute hand (130 px), cell 1 the hour hand (80 px), each from its top to the pivot
	int hand = atlas(H, 2, 16, 132, [](int i, int x, int y) { return x >= 6 && x < 10 && y < (i ? 80 : 130) ? 255 : 0; });
	const uint16_t g0[1] = { 0 }, g1[1] = { 1 };
	CHECK(el_rotation_begin(H, 192, 192, EL_EXPR_HOUR_HAND_DEG) == 0);
	CHECK(el_sprite_text(H, hand, 184, 192 - 80, 0xa0a0a0ff, 1, nullptr, g1) == 0);
	CHECK(el_group_end(H) == 0);
	CHECK(el_rotation_begin(H, 192, 192, EL_EXPR_MINUTE_ONLY_DEG) == 0);
	CHECK(el_sprite_text(H, hand, 184, 192 - 130, 0xffffffff, 1, nullptr, g0) == 0);
	CHECK(el_group_end(H) == 0);
	CHECK(writeHex(H, std::string(dir) + "/probe-hands.hex"));
	el_free(H);

	// heart rate (3 digits, y 120) and steps (5 digits, y 200), right-aligned, leading digits blank,
	// a dash in every cell where the hub gives no value (glyph 0)
	el_layout *M = withBackground();
	int dg = atlas(M, 12, 16, 24, digitPixel);
	struct Row { int prop; int digits; float y; } rows[2] = { { EL_PROP_HR_BPM, 3, 120 }, { EL_PROP_DAY_STEPS, 5, 200 } };
	for (const Row &r : rows) {
		std::vector<std::string> ex;
		for (int i = 0; i < r.digits; i++) {
			const int k = r.digits - 1 - i;      // 10^k
			long p = 1;
			for (int j = 0; j < k; j++)
				p *= 10;
			char b[128];
			if (k == 0)
				snprintf(b, sizeof(b), "({%d}%%10 + 1)", r.prop);
			else
				snprintf(b, sizeof(b), "({%d} < %ld ? 11 : ({%d}/%ld)%%10 + 1)", r.prop, p, r.prop, p);
			ex.push_back(b);
		}
		std::vector<const char *> e;
		for (const std::string &s : ex)
			e.push_back(s.c_str());
		CHECK(el_sprite_text(M, dg, 192 - 8 * r.digits, r.y, 0xffffffff, r.digits, e.data(), nullptr) == 0);
	}
	CHECK(writeHex(M, std::string(dir) + "/probe-metrics.hex"));
	el_free(M);
}

int main()
{
	functions();
	rotation();
	metrics();
	if (const char *dir = getenv("EL_PROBE_DIR"))
		probes(dir);
	printf("tst_eoslayout: %d checks, %d failures\n", checks, failures);
	return failures ? 1 : 0;
}
