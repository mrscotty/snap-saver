#!/usr/bin/env perl
#

use strict;
use warnings;

use Test::More;

use Vagrant;

my $state = Vagrant::state();
my $rc;
my $status;

my @demo_files = 
    qw( /root-fs.demo /usr/usr-fs.demo /var/var-fs.demo /home/home-fs.demo );

sub snapadm {
    my $cmd = shift;
    return Vagrant::sshcmd("/sbin/snap-adm.sh $cmd");
}

sub snapstatus {
    return Vagrant::backtick("/sbin/snap-adm.sh status");
}

# Create some demo files
sub demo_create {

    foreach my $file ( @demo_files ) {
        is(Vagrant::sshcmd("sudo touch $file"), 0, "touch demo file $file");
    }
}

# Check demo files
sub demo_ok {
    foreach my $file ( @demo_files ) {
        is(Vagrant::sshcmd("test -e $file"), 0, "test that file $file was created");
    }
}

# Check demo files
sub demo_nok {
    foreach my $file ( @demo_files ) {
        isnt(Vagrant::sshcmd("test -e $file"), 0, "test that file $file was created");
    }
}

is($state, 'running', "instance must be running") or
    BAIL_OUT("vagrant instance must be running");

#$rc = Vagrant::sshcmd("mkdir snap-pkg && cd snap-pkg && tar -xzf /vagrant/snap-saver.tgz && ./install.sh");
#is($rc, 0, "Results of installing snap-saver.tgz");

# Enable snap-saver, reboot, and check the status (output shows LVs are
# snapshots of original LVs)
is(snapadm('enable'), 0, 'enable snap-saver');
$status = snapstatus();
like($status, qr/snap-adm.sh - ENABLED/ms, 'check snap-saver is enabled');
unlike($status, qr/is snapshot of/ms, 'check no snapshots exist');

is(Vagrant::halt(), 0, 'vagrant halt');
is(Vagrant::up(), 0, 'vagrant up');
$status = snapstatus();
like($status, qr/snap-adm.sh - ENABLED/ms, 'check snap-saver is enabled');
foreach my $lv ( qw( home_lv root_lv usr_lv var_lv ) ) {
    like($status, qr/${lv} is snapshot of ${lv}_orig/ms, "check $lv snapshot enabled");
}

# Create some demo files
demo_create();
demo_ok();

# Make sure demo files disappear after reboot
is(Vagrant::halt(), 0, 'vagrant halt');
is(Vagrant::up(), 0, 'vagrant up');
demo_nok();

# Re-create the demo files
demo_create();
demo_ok();

# Turn off refresh and make sure demo files persist after reboot
is(snapadm('norefresh'), 0, 'set norefresh');
is(Vagrant::halt(), 0, 'vagrant halt');
is(Vagrant::up(), 0, 'vagrant up');
demo_ok();

$status = snapstatus();
like($status, qr/snap-adm.sh - ENABLED/ms, 'check snap-saver is enabled');
like($status, qr/snap-adm.sh - REFRESH/ms, 'check snap-saver will refresh');
foreach my $lv ( qw( home_lv root_lv usr_lv var_lv ) ) {
    like($status, qr/${lv} is snapshot of ${lv}_orig/ms, "check $lv snapshot enabled");
}

# Now try to disable completely (e.g. for installing OS updates on pristine
# system)

is(snapadm('disable'), 0, 'set disabled');
is(Vagrant::halt(), 0, 'vagrant halt');
is(Vagrant::up(), 0, 'vagrant up');
$status = snapstatus();
like($status, qr/_snap is snapshot of/ms, 'check no snapshots active');
unlike($status, qr/_orig/ms, 'check no snapshots active 2');

done_testing();

