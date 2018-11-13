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

package App::rs;

our $VERSION = 'v2.1.2';

use strict;
use warnings qw/all FATAL uninitialized/;
use feature qw/state say/;

require XSLoader;
XSLoader::load();

sub _require ($) {
	my $r = shift =~ s|::|/|gr . '.pm';
	require $r if not $INC{$r};
}
sub flatten (;$) {
	my $v = @_ ? shift : $_;
	ref $v eq 'ARRAY' ? @$v : $v;
}
BEGIN {
	no strict 'refs';
	my @H = ($^H, ${^WARNING_BITS}, %^H);
	sub import {
		my $ns = caller . '::';
		shift;
		while (@_) {
			my $q = shift;
			if ($q eq 'iautoload') {
				my (@pkg, %map);
				for (@{+shift}) {
					my ($p, @f) = flatten;
					push @pkg, $p;
					for (@f) {
						my ($from, $to) = flatten;
						$from =~ s/^([$@%&*])//;
						$to ||= $from;
						if (my $s = $1) {
							state $sigil = {'$' => 'SCALAR',
									'@' => 'ARRAY',
									'%' => 'HASH',
									'&' => 'CODE',
									'*' => 'GLOB'};
							_require $p;
							*{$ns . $to} = *{"${p}::$from"}{$sigil->{$s}};
						} else {
							$map{$to} = {from => $from,
								     module => $p};
						}
					}
				}
				*{$ns . 'AUTOLOAD'} = sub {
					# "fully qualified name of the original subroutine".
					my $q = our $AUTOLOAD;
					# to avoid possibly overwrite @_ by successful regular expression match.
					my ($to) = do { $q =~ /.*::(.*)/ };
					my $u = $map{$to};
					my $from = $u->{from} || $to;
					for my $p ($u->{module} || @pkg) {
						#   calculate the actual file to be loaded thus avoid eval and
						# checking $@ mannually.
						_require $p;
						if (my $r = *{"${p}::$from"}{CODE}) {
							no warnings 'prototype';
							*$q = $r;
							# TODO: understand why using goto will lost context.
							#goto &$r;
							return &$r;
						}
					}
					confess("unable to autoload $q.");
				};
			} elsif ($q eq 'oautoload') {
				for my $p (@{+shift}) {
					my $r = $p =~ s|::|/|gr . '.pm';
					# ignore already loaded module.
					my $f = "${p}::AUTOLOAD";
					next if $INC{$r} or *$f{CODE};
					*$f = sub {
						my ($f) = do { our $AUTOLOAD =~ /.*::(.*)/ };
						my $symtab = *{"${p}::"}{HASH};
						delete $symtab->{AUTOLOAD};
						require $r;
						&{$symtab->{$f}};
					};
				}
			} elsif ($q eq 'sane') {
				($^H, ${^WARNING_BITS}, %^H) = @H;
			} else {
				confess("unknown request $q");
			}
		}
	};
	my @a = qw/Cpanel::JSON::XS JSON::XS JSON::PP/;
	App::rs->import(iautoload => ['Carp',
				      [qw'Compress::Zlib memGunzip'],
				      [qw/File::Path make_path/],
				      [qw'Socket getaddrinfo',
				       map { "&$_" } qw'AF_UNIX SOCK_STREAM MSG_NOSIGNAL']],
			oautoload => [@a]);
	my $o;
	for (@a) {
		last if eval {
			$o = $_->new->pretty->canonical;
		};
	}
	sub jw	{ $o->encode(shift) }
	sub jr	{ $o->decode(shift) }
}
sub xsh {
	my $f = shift;
	if (not ref $f) {
		my $h = {};
		$h->{"capture-stdout"} = 1 if $f & 1;
		$h->{"feed-stdin"} = 1 if $f & 2;
		$f = $h;
	}
	my ($h, $i, $pr, @st) = ({pid => []}, 0);
	if ($f->{"feed-stdin"}) {
		my ($fi, $pid) = shift;
		pipe $pr, my $pw;
		if (not $pid = fork) {
			close $pr;
			print $pw $fi;
			exit;
		} else {
			push @{$h->{pid}}, $pid;
		}
	}
	while ($i <= @_) {
		my $l = $i == @_;
		my $a = $_[$i] if not $l;
		if ($l or $a eq "|") {
			pipe my $r, my $w if not $l or $f->{"capture-stdout"};
			# there's no need to fork when executing the last command and we're required
			# to substitute current process.
			my $pid = fork unless $l and $f->{substitute};
			if (not $pid) {
				# always true except possibly the first.
				open STDIN, "<&", $pr if $pr;
				# always true except possibly the last.
				open STDOUT, ">&", $w if $w;
				while (ref $st[-1]) {
					my ($h, $f) = pop @st;
					if (ref \$h->{from} eq "SCALAR")	{ open $f, $h->{mode}, $h->{from} or die $! }
					else					{ $f = $h->{from} }
					open $h->{to}, $h->{mode} . "&", $f;
				}
				exec @st;
			} else {
				$pr = $r;
				push @{$h->{pid}}, $pid;
				@st = ();
			}
		} else {
			push @st, $a;
		}
		$i++;
	}
	if ($f->{asynchronous}) {
		$h->{stdout} = $pr if $f->{"capture-stdout"};
		if ($f->{compact})		{ $h }
		elsif ($f->{"capture-stdout"})	{ $pr }
		else				{ wantarray ? @{$h->{pid}} : $h->{pid}[-1] }
	} else {
		if ($f->{"capture-stdout"}) {
			local $/ if not wantarray;
			$h->{stdout} = [<$pr>];
		}
		$h->{status} = [];
		push @{$h->{status}}, waitpid($_, 0) == -1 ? undef : $? for @{$h->{pid}};
		# they're meaningless now as they don't exist anymore.
		delete $h->{pid};
		if ($f->{compact})		{ $h }
		elsif ($f->{"capture-stdout"})	{ wantarray ? @{$h->{stdout}} : $h->{stdout}[0] }
		else				{ wantarray ? @{$h->{status}} : not $h->{status}[-1] }
	}
}
sub arg_parse {
	my $h = {};
	while (@ARGV) {
		my $a = shift @ARGV;
		if ($a !~ /^-/)			{ unshift @ARGV, $a; last }
		elsif ($a =~ /^--?$/)		{ last }
		elsif ($a =~ /^--(.*?)=(.*)$/)	{ hash_madd_key($h, $1, $2) }
		elsif ($a =~ /^--?(.*)$/)	{ $h->{$1} = 1 }
	}
	$h;
}
sub hash_madd_key {
	my ($h, $k, $v) = @_;
	if (exists $h->{$k}) {
		$h->{$k} = [$h->{$k}] if ref $h->{$k} ne 'ARRAY';
		push @{$h->{$k}}, $v;
	} else {
		$h->{$k} = $v;
	}
}
sub linker {
	my $s = shift;
	$s->{i386} ?
	    "$s->{prefix}/lib/ld-linux.so.2" : $s->{arm} ?
	    "$s->{prefix}/lib/ld-linux-armhf.so.3" :
	    "$s->{prefix}/lib/ld-linux-x86-64.so.2";
}
sub add {
	my $h = shift;
	while (@_) {
		my ($k, $v) = splice @_, 0, 2;
		$h->{$k} = $v;
	}
}
sub slice {
	my $h = shift;
	map { $_ => $h->{$_} } @_;
}
sub wf {
	local $_ = shift;
	if (-e) {
		if (-f)	{ unlink or die "$!: unable to remove $_ for writing.\n" }
		else	{ die "What's $_?" unless $_ eq '/dev/null' }
	} elsif (m|(.*/)|) {
		make_path($1) unless -d $1;
	}
	open my $fh, '>', $_ or die "open $_ for writing: $!";
	if (@_)	{ syswrite $fh, shift }
	else	{ $fh }
}
sub purl {
	my $o = shift;
	my $x = {major => 1,
		 minor => 1,
		 type => 'request',
		 method => $o->{method},
		 hf => [qw/Host User-Agent Accept-Encoding Connection/],
		 hv => {connection => 'keep-alive',
			'user-agent' => 'App-rs',
			'accept-encoding' => 'gzip'}};
	if ($o->{method} eq 'POST') {
		push @{$x->{hf}}, qw/Content-Length Content-Type/;
		add($x->{hv},
		    'content-length' => undef,
		    'content-type' => 'application/x-www-form-urlencoded');
		$x->{c} = $o->{'post-data'};
	}
	my $url = $o->{url};
	@$x{qw/protocol request-uri/} = ('http', '/');
	($x->{protocol}, $url) = ($1, $2) if $url =~ m|(.*)://(.*)|;
	if ($url =~ m|(.*?)(/.*)|) {
		($x->{hv}{host}, $x->{'request-uri'}) = ($1, $2);
	} else {
		$x->{hv}{host} = $url;
	}
	my $r = http_req($x);
	my $c = $r->{c};
	$c = memGunzip($c) if eval { $r->{hv}{'content-encoding'} eq 'gzip' };
	if ($o->{json})		{ jr($c) }
	elsif ($o->{plain})	{ $c }
	elsif ($o->{html})	{ html_parse($c) }
	elsif ($o->{save})	{
		die $r->{b} unless $r->{'status-code'} == 200;
		wf($o->{save}, $c);
	}
}
sub http_req {
	# socket pool.
	state $pool = {};
	my ($x, $f) = @_;
	# host key to identify socket.
	my $hk = $x->{protocol} . '://' . $x->{hv}{host};
	if (not $pool->{$hk}) {
		say "creating new pool socket $hk.";
		if ($x->{protocol} eq 'https')	{ $pool->{$hk} = connect_tls($x->{hv}{host}, 443) }
		else				{ $pool->{$hk} = connect_tcp($x->{hv}{host}, 80) }
	}
	send $pool->{$hk}, http_unparse($x), MSG_NOSIGNAL;
	my $h = http_parse_new();
	# avoid undefined warning when checking length of $h->{c}.
	$h->{c} = '';
	while (1) {
		my $b;
		eval {
			local $SIG{ALRM} = sub { die };
			alarm 12;
			recv $pool->{$hk}, $b, 1048576, 0;
			alarm 0;
		};
		if ($@ or not $b) {
			if ($@)	{ say 'timeout.' }
			else	{ say 'remote-close.' }
			my $_h = http_parse_new();
			if ($f->{range} and length($h->{c})) {
				$_h->{c} = $h->{c};
				push @{$x->{hf}}, 'Range' if not exists $x->{hv}{range};
				$x->{hv}{range} = 'bytes=' . length($h->{c}) . '-';
			}
			$h = $_h;
			if ($x->{protocol} eq 'https')	{ $pool->{$hk} = connect_tls($x->{hv}{host}, 443) }
			else				{ $pool->{$hk} = connect_tcp($x->{hv}{host}, 80) }
			send $pool->{$hk}, http_unparse($x), MSG_NOSIGNAL;
		} else {
			return $h if http_parse($h, $b);
		}
	}
}
sub connect_tcp {
	my ($err, $a) = getaddrinfo(@_);
	die "getaddrinfo: $err" if $err;
	socket my $fh, $a->{family}, SOCK_STREAM, 0 or die $!;
	connect $fh, $a->{addr} or die $!;
	$fh;
}
sub connect_tls {
	my ($host, $port) = @_;
	my ($p, $q);
	socketpair $p, $q, AF_UNIX, SOCK_STREAM, 0;
	xsh({asynchronous => 1}, qw/socat -/, "OPENSSL:$host:$port",
	    {to => *STDIN,
	     from => $q,
	     mode => '<'}, {to => *STDOUT,
			    from => $q,
			    mode => '>'});
	$p;
}
sub http_parse_new {
	{st => 'reading-header',
	 # remaining length.
	 rl => 'line',
	 # header value.
	 hv => {},
	 # header field.
	 hf => [],
	 # first line.
	 fl => 1};
}
sub http_parse {
	my ($h, $b) = @_;
	$h->{b} .= $b;
	my $i = 0;
	while ($i < length($b)) {
		if ($h->{rl} eq "line") {
			pos($b) = $i;
			if ($b =~ /\n/g) {
				$h->{l} .= substr($b, $i, pos($b) - $i), $i = pos($b);
				$h->{l} =~ s/\r?\n$//;
				if ($h->{st} eq "reading-header") {
					if ($h->{fl}) {
						if ($h->{l}) {
							if ($h->{l} =~ m|^HTTP\s*/\s*(\d)\s*\.\s*(\d)\s+(\d{3})\s+(.*)$|) {
								@$h{qw/type major minor status-code reason-phrase/} = ("reply", $1, $2, $3, $4);
							} elsif ($h->{l} =~ m|^(.*?)\s+(.*?)\s+HTTP\s*/\s*(\d)\s*\.\s*(\d)$|) {
								@$h{qw/type method request-uri major minor/} = ("request", $1, $2, $3, $4);
							} else {
							}
							$h->{fl} = 0;
						}
						# empty line before request/reply ignored.
					} else {
						if (not $h->{l}) {
							if ($h->{type} eq "reply" and $h->{"status-code"} =~ /^(1\d{2}|204|304)$/) {
								return $i;
							} elsif (exists $h->{hv}{"transfer-encoding"} and $h->{hv}{"transfer-encoding"} !~ /^identity$/i) {
								$h->{st} = "reading-chunk-size";
							} elsif (exists $h->{hv}{"content-length"}) {
								$h->{rl} = $h->{hv}{"content-length"}, $h->{st} = "reading-content";
								# content-length could be 0.
								return $i if not $h->{rl};
							} elsif ($h->{type} eq "reply") {
								$h->{rl} = "eof";
							} else {
								return $i;
							}
						} elsif ($h->{l} =~ /^\s/) {
							my $k = lc $h->{hf}[$#{$h->{hf}}];
							if (ref $h->{hv}{$k} eq "ARRAY") {
								my $r = $h->{hv}{$k};
								$r->[$#$r] .= $h->{l};
							} else {
								$h->{hv}{$k} .= $h->{l};
							}
						} else {
							my ($f, $v) = $h->{l} =~ /^(.*?)\s*:\s*(.*?)\s*$/;
							my $k = lc($f);
							if (exists $h->{hv}{$k}) {
								if (ref $h->{hv}{$k} eq "ARRAY") {
									push @{$h->{hv}{$k}}, $v;
								} else {
									$h->{hv}{$k} = [$h->{hv}{$k}, $v];
								}
							} else {
								$h->{hv}{$k} = $v;
							}
							push @{$h->{hf}}, $f;
						}
					}
				} elsif ($h->{st} eq "reading-chunk-size") {
					$h->{l} =~ /^([A-Fa-f0-9]+)/;
					if ($1 !~ /^0+$/)	{ $h->{rl} = hex $1, $h->{st} = "reading-chunk-data" }
					else			{ $h->{st} = "reading-trailer" }
				} elsif ($h->{st} eq "reading-crlf") {
					$h->{st} = "reading-chunk-size";
				} elsif ($h->{st} eq "reading-trailer") {
					# trailer ignored.
					return $i unless $h->{l};
				}
				$h->{l} = "";
			} else {
				$h->{l} .= substr($b, $i), $i = length($b);
			}
		} else {
			if ($h->{rl} ne "eof" and $h->{rl} <= length($b) - $i) {
				$h->{c} .= substr($b, $i, $h->{rl}), $i += $h->{rl};
				if ($h->{st} eq "reading-chunk-data")	{ $h->{rl} = "line", $h->{st} = "reading-crlf" }
				else					{ return $i }
			} else {
				$h->{c} .= substr($b, $i), $h->{rl} -= length($b) - $i, $i = length($b);
			}
		}
	}
	undef;
}
sub http_unparse {
	my $h = shift;
	my $b;
	my $v = "HTTP/$h->{major}.$h->{minor}";
	if ($h->{type} eq "request")	{ $b = join " ", $h->{method}, $h->{"request-uri"}, $v }
	else				{ $b = join " ", $v, $h->{"status-code"}, $h->{"reason-phrase"} }
	$b .= "\r\n";
	$h->{hv}{"content-length"} = length($h->{c}) if exists $h->{hv}{"content-length"};
	my $i = {};
	for (@{$h->{hf}}) {
		$b .= "$_: ";
		my $k = lc $_;
		if (ref $h->{hv}{$k} eq "ARRAY")	{ $b .= $h->{hv}{$k}[$i->{$k}++] }
		else					{ $b .= $h->{hv}{$k} }
		$b .= "\r\n";
	}
	$b .= "\r\n";
	if (exists $h->{c}) {
		if (exists $h->{hv}{"transfer-encoding"} and $h->{hv}{"transfer-encoding"} !~ /^identity$/i) {
			$b .= sprintf("%x\r\n", length($h->{c})) . $h->{c} . "\r\n0\r\n\r\n";
		} else {
			$b .= $h->{c};
		}
	}
	$b;
}
sub vcmp ($$) {
	my ($a, $b) = @_;
	version->parse($a) <=> version->parse($b);
}
sub vsat {
	my ($pkg, $ver) = @_;
	return vcmp($^V, $ver) >= 0 if $pkg eq 'perl';
	if (my $pid = fork) {
		die unless $pid == waitpid $pid, 0;
		not $?;
	} else {
		exit not eval {
			require $pkg =~ s|::|/|gr . '.pm';
			$pkg->VERSION($ver);
		};
	}
}
sub rf {
	local (@ARGV, $/) = @_;
	<>;
}
1;
