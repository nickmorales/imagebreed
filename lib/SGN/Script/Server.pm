package SGN::Script::Server;
use Moose;
use SGN::Devel::MyDevLibs;

use SGN::Exception;

extends 'Catalyst::Script::Server';

if (@ARGV && "-r" ~~ @ARGV) {
    $ENV{SGN_WEBPACK_WATCH} = 1;

    if ($ENV{MODE} && $ENV{MODE} eq 'DEVELOPMENT') {
        system("cd js && npm run build-watch &");
    }
    else {
        system("cd js && npm run build-ci-watch &");
    }
}

1;
