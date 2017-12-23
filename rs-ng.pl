#!/usr/bin/env perl
=license

	Copyright © 2018 Yang Bo

	This file is part of RSLinux.

	RSLinux is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	RSLinux is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with RSLinux.  If not, see <http://www.gnu.org/licenses/>.

=cut
use c iautoload => [qw/c cxs rs dot/], 'constant', 'sane';

main();

sub set {
	my ($f, $mode, $uid, $gid, $mtime) = @_;
	# chown should be called before chmod to prevent setuid, setgid bit gets reset.
	chown $uid, $gid, $f and chmod $mode & 07777, $f and utimensat($f, $mtime) or die "$f: $!";
}
sub equiv {
	my ($p, $q) = @_;
	no warnings 'uninitialized';
	not grep { $p->{$_} ne $q->{$_} } qw/mode uid gid size mtime hl sl/;
}
sub elf {
	my ($f, $v) = shift;
	mmap($f, my $b);
	$v = 1 if length $b >= 4 and substr($b, 0, 4) eq "\x7fELF";
	munmap($b, length $b);
	$v;
}
sub strip {
	my ($f, $m, $root) = @_;
	my $s = {};
	if (/\.[ao]$/)						{ @$s{qw/strip archive/} = (1, 1) }
	elsif ((/\.so/ or $m->{mode} & 0111) and elf($f))	{ $s->{strip} = 1 }
	if ($s->{strip}) {
		xsh(0, 'strip', $s->{archive} ? '--strip-unneeded' : (), $f);
		say "strip on $f, st: $?.";
		if (not $?) {
			set($f, @$m{qw/mode uid gid mtime/});
			$m->{size} = (stat $f)[7];
		}
	}
}
sub diff {
	my ($cp, $vp) = @_;
	my ($db, $v) = ($vp->{db}, {});
	opendir(my $dh, $cp->{root} . $vp->{d}) or die $!;
	for (sort readdir $dh) {
		my $ign = $vp->{ign}{$_};
		# ignore leaf only.
		next if /^\.{1,2}$/ or $ign and not ref $ign;
		my ($r, $f, $m) = ($vp->{d} . $_, $cp->{root} . $vp->{d} . $_, {});
		(my $i, @$m{qw/mode uid gid size mtime/}) = (lstat $f)[1, 2, 4, 5, 7, 9];
		if ($cp->{ih}{$i})	{ $m->{hl} = $cp->{ih}{$i} }
		else			{ $cp->{ih}{$i} = $r }
		my $t = $m->{mode} & S_IFMT;
		if ($t == S_IFDIR)	{ delete $m->{size} }
		elsif ($t == S_IFLNK)	{ $m->{sl} = readlink $f or die $! }
		elsif ($t != S_IFREG)	{ die "unknown type $t of $f." }
		my $st = {};
		if (my $_m = $db->{$_}) {
			my $_t = $_m->{mode} & S_IFMT;
			if ($t == S_IFDIR xor $_t == S_IFDIR)	{ ... }
			elsif ($t == S_IFDIR)			{ $st->{dir} = 1 }
			else					{ $st->{mod} = 1 if not equiv($m, $_m) }
		} else {
			$st->{ne} = 1;
		}
		if (%$st) {
			if ($t == S_IFDIR) {
				my $p = $db->{$_} = {%$m,
						     c => $db->{$_}{c},
						     owner => $db->{$_}{owner}};
				$p->{c} = {} if not $p->{c};
				my $c = diff($cp, {db => $p->{c},
						   ign => $vp->{ign}{$_},
						   d => $r . '/'});
				if ($st->{ne} or %$c) {
					$v->{$_} = {%$m,
						    c => $c};
					$p->{owner}{$cp->{oid}} = $cp->{ts};
				}
			} else {
				my $n = 1 if $t == S_IFREG and not $m->{hl};
				strip($f, $m) if $n;
				my $p = $db->{$_} = {%$m,
						     owner => $db->{$_}{owner}};
				$p->{owner}{current} = $cp->{oid}, $p->{owner}{record}{$cp->{oid}} = $cp->{ts};
				$v->{$_} = {%$m};
				$v->{$_}{c} = \$f if $n;
			}
		}
	}
	$v;
}
sub patch {
	my ($cp, $vp) = @_;
	my ($db, $v) = @$vp{qw/db v/};
	for (sort keys %$v) {
		my ($r, $f, $q) = ($vp->{d} . $_, $cp->{root} . $vp->{d} . $_, $v->{$_});
		#my $t = $q->{mode} & S_IFMT;
		my $t = $q->{sl} ? S_IFLNK : $q->{mode} & S_IFMT;
		if ($t == S_IFDIR) {
			if (not $db->{$_}) {
				mkdir $f or die "mkdir $f: $!";
				$db->{$_} = {%$q,
					     c => {}};
			}
			my $p = $db->{$_};
			patch($cp, {v => $q->{c},
				    db => $p->{c},
				    d => $r . '/'});
			set($f, @$p{qw/mode uid gid mtime/}) if not $p->{owner};
			$p->{owner}{$cp->{oid}} = $cp->{ts};
		} else {
			my $p = $db->{$_} = {%$q,
					     owner => $db->{$_}{owner}};
			unlink $f or die "$f exists but unable to unlink." if -e $f;
			if ($t == S_IFREG) {
				if ($p->{hl}) {
					my $g = $cp->{root} . $p->{hl};
					link $g, $f or die "unable to hard link $f to $g: $!";
				} else {
					wf($f, delete $p->{c});
					set($f, @$p{qw/mode uid gid mtime/});
				}
			} else {
				#unlink $f or die "unable to remove $f for symbolic linking.\n" if -e $f;
				symlink $p->{sl}, $f or die "unable to symlink $f to $p->{sl}: $!.";
				# symlink(7) explicitly says the permission of a symbolic link can't be changed(on Linux).
				lchown($f, @$p{qw/uid gid/}) and utimensat($f, $p->{mtime}) or die "$f: $!";
			}
			$p->{owner}{current} = $cp->{oid}, $p->{owner}{record}{$cp->{oid}} = $cp->{ts};
		}
	}
}
# merge two patch trees, the first one takes higher priority.
sub merge {
	my ($p, $q) = @_;
	for (keys %$q) {
		if (not $p->{$_}) {
			$p->{$_} = $q->{$_};
		} else {
			my ($t, $_t) = ($p->{$_}{mode} & S_IFMT, $q->{$_}{mode} & S_IFMT);
			if ($t == S_IFDIR xor $_t == S_IFDIR)	{ ... }
			elsif ($t == S_IFDIR)			{ merge($p->{$_}{c}, $q->{$_}{c}) }
		}
	}
}
# add path r from v to p.
sub grow {
	my ($p, $v, $r) = @_;
	my @d = split m|/|, $r;
	my $f = pop @d;
	for (@d) {
		$p->{$_} = {%{$v->{$_}},
			    c => {}} if not $p->{$_};
		$p = $p->{$_}{c}, $v = $v->{$_}{c};
	}
	$p->{$f} = $v->{$f};
}
sub rm {
	my ($cp, $vp) = @_;
	my $db = $vp->{db};
	for (keys %$db) {
		my ($r, $f, $p, $o) = ($vp->{d} . $_, $cp->{root} . $vp->{d} . $_, $db->{$_}, $db->{$_}{owner});
		if ($p->{c}) {
			if ($o->{$cp->{oid}}) {
				rm($cp, {db => $p->{c},
					 d => $r . '/'});
				delete $o->{$cp->{oid}};
				if (not %$o) {
					rmdir $f or die "unable to rmdir $f: $!.";
					delete $db->{$_};
				}
			}
		} else {
			if ($o->{record}{$cp->{oid}}) {
				delete $o->{record}{$cp->{oid}};
				if ($o->{current} eq $cp->{oid}) {
					unlink $f or warn "unable to unlink $f: $!.";
					if (%{$o->{record}}) {
						my $oid;
						for (keys %{$o->{record}}) {
							$oid = $_ if not $oid or $o->{record}{$_} > $o->{record}{$oid};
						}
						my $p = $cp->{patch};
						if (not $p->{$oid}) {
							my $v = rs_parse($cp->{pool} . $oid . '.rs');
							$p->{$oid} = {v => $v,
								      p => {}};
						}
						grow(@{$p->{$oid}}{qw/p v/}, $r);
					} else {
						delete $db->{$_};
					}
				}
			}
		}
	}
}
sub wf {
	my $f = shift;
	unlink $f or die "$!: unable to remove $f for writing.\n" if -e $f;
	open my $fh, '>', $f or die "open $f for writing: $!";
	if (@_)	{ syswrite $fh, shift }
	else	{ $fh }
}
sub priv {
	my $f = shift;
	my ($uid, $gid) = (getpwnam $ENV{USER})[2, 3];
	if (not $f) {
		($(, $)) = ($gid, "$gid $gid");
		setresuid($uid, $uid, 0);
	} else {
		setresuid(0, 0, 0);
		($(, $)) = (0, '0 0');
	}
}
sub tag {
	my ($cp, $vp) = @_;
	my ($v, $oid, $db, $d) = ({}, $cp->{oid}, @$vp{qw/db d/});
	say {$cp->{sink}} $d;
	for (keys %$db) {
		my ($p, $r) = ($db->{$_}, $d . $_);
		if ($p->{c}) {
			$v->{$_} = {%$p,
				    c => tag($cp, {db => $p->{c},
						   d => $r . '/'})} if $p->{owner}{$oid};
		} else {
			$v->{$_} = $p, say {$cp->{sink}} $r if $p->{owner}{record}{$oid};
		}
	}
	$v;
}
sub confirm () {
	chomp(my $a = <STDIN>);
	exit unless $a;
}
sub main {
	my $s;
	do {
		my $c = arg_parse();
		$s = $c->{profile} ? do $c->{profile} : do "$ENV{HOME}/.rs.profile" || {};
		add($s, %$c);
	};
	print 'run-time config: ', json_unparse_readable($s);
	# mod tells us whether the database is modified.
	my ($db, $mod) = rs_parse($s->{db});
	while (@ARGV) {
		my $op = shift @ARGV;
		if ($op eq 'diff') {
			my $oid = shift @ARGV;
			my ($p, $_v) = $s->{pool} . $oid . '.rs';
			if (-e $p) {
				say "$p exists, will merge with new generated patch tree.";
				$_v = rs_parse($p);
			}
			my $v = diff({ih => {},
				      root => $s->{root},
				      oid => $oid,
				      ts => time}, {db => $db,
						    ign => $s->{ign} ? do $s->{ign} : undef,
						    d => ''});
			$mod = 1;
			merge($v, $_v) if $_v;
			rs_unparse($v, fileno wf($p));
		} elsif ($op eq 'patch') {
			my $f = shift @ARGV;
			#   v is the parsed value of the patch, and can be cut using subtree switch,
			# the final patch to apply is stored in p.
			my $v = my $p = rs_parse($f);
			if (exists $s->{subtree}) {
				$p = {};
				grow($p, $v, $_) for flatten($s->{subtree});
			}
			my ($oid) = $f =~ m|([^/]*).rs$|;
			patch({root => $s->{root},
			       oid => $oid,
			       ts => time}, {v => $p,
					     db => $db,
					     d => ''});
			$mod = 1;
		} elsif ($op eq 'remove') {
			my $oid = shift @ARGV;
			rm({root => $s->{root},
			    oid => $oid,
			    pool => $s->{pool},
			    patch => my $p = {}}, {db => $db,
						   d => ''});
			$mod = 1;
			my $ts = time;
			for (keys %$p) {
				patch({root => $s->{root},
				       oid => $_,
				       ts => $ts}, {v => $p->{$_}{p},
						    db => $db,
						    d => ''});
			}
		} elsif ($op eq 'compile') {
			# drop root privilege before compile, as suggested by many packages.
			priv(0);
			my ($p, $oid, $pkg, $d, $git) = shift @ARGV;
			if ($git = -d $p) {
				$oid = shift @ARGV;
				$d = $p;
			} else {
				($oid) = $p =~ m|([^/]*).tar.*$|;
				($d) = (xsh(1, qw/tar -xvf/, $p))[0] =~ m|([^/\n]*)| or die 'bad tarball.';
			}
			($pkg) = $oid =~ m|(.*)-|;
			my $_d = readlink '/proc/self/cwd' or die "readlink: $!.";
			chdir $d or die "chdir $d: $!.";
			my $b = (do $s->{build})->($s)->{$pkg};
			xsh({'feed-stdin' => 1}, $b->{'pre-configure'}, 'bash') or die 'pre-configure failed.' if $b->{'pre-configure'};
			unless ($b->{'no-configure'}) {
				local %ENV = %ENV;
				xsh(0, qw/autoreconf -iv/) or die 'autoreconf failed.' unless -e 'configure';
				my @p;
				if ($s->{bootstrap}) {
					$ENV{CPPFLAGS} = '-I/p/include' unless $b->{'no-cppflags'};
					$ENV{LDFLAGS} = '-L/p/lib -Wl,-I' . ($s->{i386} ?
									     '/p/lib/ld-linux.so.2' : $s->{arm} ?
									     '/p/lib/ld-linux-armhf.so.3' :
									     '/p/lib/ld-linux-x86-64.so.2');
					push @p, '--prefix=/p';
				} else {
					push @p, '--prefix=/usr';
				}
				my $e = $b->{environment};
				$ENV{$_} = $e->{$_} for keys %$e;
				xsh(0, './configure', @{$b->{switch}}, @p,
				    {to => *STDERR,
				     from => *STDOUT,
				     mode => '>'}, qw/| less -KR/) or die 'configure failed.';
			}
			xsh({'feed-stdin' => 1}, $b->{'post-configure'}, 'bash') or die 'post-configure failed.' if $b->{'post-configure'};
			xsh(0, 'make', $s->{jobs} ? "--jobs=$s->{jobs}" : (), @{$b->{'make-parameter'}}) or die 'make failed.' unless $b->{'no-make'};
			xsh({'feed-stdin' => 1}, $b->{'post-make'}, 'bash') or die 'post-make failed.' if $b->{'post-make'};
			priv(1);
			xsh(0, qw/make install/, @{$b->{'make-install-parameter'}}) or die 'make install failed.';
			xsh({'feed-stdin' => 1}, $b->{'post-make-install'}, 'bash') or die 'post-make failed.' if $b->{'post-make-install'};
			my $cwd = readlink '/proc/self/cwd' or die $!;
			# do some cleaning.
			if ($git) {
				say "will 'git clean -fdx' on $cwd.";
				confirm;
				xsh(0, qw/git clean -fdx/);
			} else {
				# remove uncompressed tarball.
				say "will 'rm -rf ../$d' on $cwd.";
				confirm;
				xsh(0, qw/rm -rf/, "../$d");
			}
			chdir $_d or die "chdir $_d: $!.";
			# the next steps.
			push @ARGV, 'diff', $oid, 'tag', $oid;
		} elsif ($op eq 'tag') {
			my ($oid, $pid) = shift @ARGV;
			do {
				pipe my $r, my $w or die $!;
				$pid = xsh({asynchronous => 1},
					   qw/less -R/, {to => *STDIN,
							 from => $r,
							 mode => '<'});
				close $r;
				print $w json_unparse_readable(tag({oid => $oid,
								    sink => $w}, {db => $db,
										  d => ''}));
			};
			# we must wait here or we will lose control-terminal.
			waitpid $pid, 0;
		}
	}
	rs_unparse($db, fileno wf($s->{db})) if $mod;
}
