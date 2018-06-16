use App::rs 'sane', 'iautoload' => [['Test', map { "&$_" } qw/plan ok/]];

plan tests => 1;
ok 1;
