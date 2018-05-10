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
require Devel::PPPort;
Devel::PPPort::WriteFile();
use ExtUtils::MakeMaker;
my $me = '://github.com/057a3dd61f99517a3afea0051a49cb27994f94d/rslinux';
WriteMakefile(NAME => 'App::rs',
	      ABSTRACT => 'package manager of RSLinux',
	      AUTHOR => ['Yang Bo <rslovers@yandex.com>'],
	      EXE_FILES => ['bin/rs'],
	      MAN3PODS => {},
	      VERSION => v1.01.001,
	      META_MERGE => {resources => {repository => {type => 'git',
							  url => "git$me.git",
							  web => "https$me"},
					   homepage => "https$me",
					   bugtracker => {web => "https$me/issues"}},
			     'meta-spec' => {version => 2}},
	      LICENSE => 'gpl_3');
