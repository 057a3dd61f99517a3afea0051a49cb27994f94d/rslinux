#define FUSE_USE_VERSION 34
#include <fuse_lowlevel.h>

#include <vector>
#include <memory>
#include <algorithm>

#include "Perl.hpp"
#include "fuse.h"

#undef NDEBUG
#include <cassert>

using namespace std;
using namespace Perl;

static SVPP	o;

static inline SVPP nodeof(fuse_ino_t i) {
	return i == 1 ? o["root"] : SVPP(reinterpret_cast<HV*>(i));
}
static void rs_stat(SVPP &p, struct stat &b, fuse_ino_t ino) {
	b.st_ino	= ino;
	b.st_mode	= p["mode"];
	b.st_uid	= p["uid"];
	b.st_gid	= p["gid"];
	if ((b.st_mode & S_IFMT) != S_IFDIR)
		b.st_size	= p["size"];
	b.st_mtime	= p["mtime"];
	b.st_nlink = 12;
}
static inline void follow(SVPP &p) {
	if (p["hl"])
		p = perlcall(o["follow"], SVPP::AL{p["hl"]}, G_SCALAR);
}
static void rs_lookup(fuse_req_t req, fuse_ino_t parent, const char *name) {
	SVPP	p(nodeof(parent));
	if (SVPP &&q{p["c"][name]}) {
		follow(q);
		struct fuse_entry_param	e{};
		e.ino = reinterpret_cast<decltype(e.ino)>(static_cast<HV*>(q));
		rs_stat(q, e.attr, e.ino);
		fuse_reply_entry(req, &e);
	} else {
		fuse_reply_err(req, ENOENT);
	}
}
static void rs_getattr(fuse_req_t req, fuse_ino_t ino,
		       struct fuse_file_info *fi) {
	SVPP	p(nodeof(ino));
	struct stat	attr{};
	rs_stat(p, attr, ino);
	fuse_reply_attr(req, &attr, 0);
}
static void rs_readlink(fuse_req_t req, fuse_ino_t ino) {
	SVPP	p(nodeof(ino));
	fuse_reply_readlink(req, p["sl"].operator string().data());
}
static void rs_open(fuse_req_t req, fuse_ino_t ino,
		    struct fuse_file_info *fi) {
	if ((fi->flags & O_ACCMODE) != O_RDONLY)
		fuse_reply_err(req, EACCES);
	else
		fuse_reply_open(req, fi);
}
static void rs_read(fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
		    struct fuse_file_info *fi) {
	SVPP	p(nodeof(ino));
	fuse_reply_buf(req, static_cast<const char*>(p["c"])+off, min(size, static_cast<UV>(p["size"])-off));
}
static void rs_readdir(fuse_req_t req, fuse_ino_t ino, size_t size, off_t off,
		       struct fuse_file_info *fi) {
	SVPP	p(nodeof(ino));
	auto	b = make_unique<char[]>(size);
	off_t	i = 0, j = 0;
	for (auto &q : p["c"]) {
		if (i >= off) {
			struct stat	attr;
			follow(q.value);
			attr.st_ino = reinterpret_cast<decltype(attr.st_ino)>(static_cast<HV*>(q.value));
			attr.st_mode = q.value["mode"] & S_IFMT;
			auto	k = fuse_add_direntry(req, &b[j], size-j,
						      q.key, &attr,
						      i+1);
			if (j+k <= size)	j += k;
			else			break;
		}
		i += 1;
	}
	fuse_reply_buf(req, &b[0], j);
}
static const struct fuse_lowlevel_ops rs_oper =
	[]() {
		struct fuse_lowlevel_ops	v{};
		v.lookup = rs_lookup;
		v.getattr = rs_getattr;
		v.readlink = rs_readlink;
		v.open = rs_open;
		v.read = rs_read;
		v.readdir = rs_readdir;
		return v;
	}();
void fuse_main(HV *_) {
	o = _;

	int	argc;
	vector<char*>	argv;

	do {
		const SVPP	&args{o["args"]};
		argc = args.size();
		for (const auto &i : args)
			argv.push_back(i.value);
		argv.push_back(nullptr);
	} while (0);

	struct fuse_args	args = FUSE_ARGS_INIT(argc, argv.data());
	struct fuse_session	*se;
	struct fuse_cmdline_opts	opts;

	assert(fuse_parse_cmdline(&args, &opts) == 0);
	if (opts.show_help) {
		fuse_cmdline_help();
		fuse_lowlevel_help();
		return;
	}
	assert(opts.mountpoint &&
	       (se = fuse_session_new(&args, &rs_oper,
				      sizeof(rs_oper), NULL)) &&
	       fuse_set_signal_handlers(se) == 0 &&
	       fuse_session_mount(se, opts.mountpoint) == 0);

	fuse_daemonize(opts.foreground);
	fuse_session_loop(se);

	fuse_session_unmount(se);
	fuse_remove_signal_handlers(se);
	fuse_session_destroy(se);
	free(opts.mountpoint);
	fuse_opt_free_args(&args);
}
