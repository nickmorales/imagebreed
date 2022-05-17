package SGN::Script::Server;
use Moose;
use SGN::Devel::MyDevLibs;

use SGN::Exception;

extends 'Catalyst::Script::Server';

if (@ARGV && "-r" ~~ @ARGV) {
    $ENV{SGN_WEBPACK_WATCH} = 1;

    my $uid = (lstat("js/package.json"))[4];
    my $user_exists = `id $uid 2>&1`;
    if ($user_exists =~ /no such user/) {
        `useradd -u $uid -m devel`;
    }

    if ($ENV{MODE} && $ENV{MODE} eq 'DEVELOPMENT') {
        system("cd js && sudo -u \\#$uid npm run build-watch &");
    }
    else {
        system("cd js && sudo -u \\#$uid npm run bbuild-ci-watch &");
    }
}

1;
