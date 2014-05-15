#!/usr/bin/env perl
#

use strict;
use warnings;

use Test::More;

use Vagrant;

my $state = Vagrant::state();
my $rc;

is($state, 'not created', "initial state");

Vagrant::up();

$state = Vagrant::state();
is($state, 'running', "state after 'up'");

# Install software
$rc = Vagrant::sshcmd("mkdir -p snap-pkg && cd snap-pkg && tar -xzf /vagrant/snap-saver.tgz && ./install.sh");
is($rc, 0, "Results of installing snap-saver.tgz");

# Initialize boot loader (WARNING - causes VM instance to re-boot)
$rc = Vagrant::sshcmd("/sbin/snap-adm.sh init");
is($rc, 0, "Results of initializing snap-saver");

# Re-boot instance
is(Vagrant::halt(), 0, "halt vagrant instance");
is(Vagrant::state(), 'poweroff', "after halt vagrant instance");
is(Vagrant::up(), 0, "up vagrant instance");
is(Vagrant::state(), 'running', "after starting vagrant instance");

like(Vagrant::backtick("/sbin/snap-adm.sh status"), qr/NOT ENABLED/, 
    "installed, but not enabled");

done_testing();
