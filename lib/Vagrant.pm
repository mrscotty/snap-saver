package Vagrant;

my $vagdir = $ENV{'VAG_DIR'} || '.';
my $sshcfg = 'default.sshcfg';

=head2 Vagrant::up

Runs 'vagrant up'. Any args are passed as arguments on the command line.

=cut

sub up {
    my @cmd = ( 'vagrant', 'up', @_ );
    my $rc = system(@cmd);
}

=head2 Vagrant::halt

Runs 'vagrant halt'. Any args are passed as arguments on the command line.

=cut

sub halt {
    my @cmd = ( 'vagrant', 'halt', @_ );
    my $rc = system(@cmd);
}



=head2 Vagrant::state [name]

Returns vagrant state for the given VM name. If no I<name> is given,
I<default> is used.

=cut

sub state {
    my $name = shift || 'default';
    my @status = `vagrant status`;
    my $state;

    if ( $status[0] =~ /^Current machine states:/ ) {
        shift @status; shift @status;
    } else {
        die "Invalid output from 'vagrant status': ", join(', ', @status);
    }
    while( $status[0] =~ m{^(\S+)\s+([^(]+)\s+[(]} ) {
        my ($key, $value) = ($1, $2);
        if ($key eq $name) {
            return $value;
        }
    }
    return;
}

=head2 Vagrant::sshcmd COMMAND [, NAME]

Runs the given command on the Vagrant instance via SSH. An optional instance
NAME may be specified. The return code from ssh is returned.

=cut

sub sshcmd {
    my $cmd = shift;
    my $name = shift || 'default';

    my @command;
    if ( -f $sshcfg ) {
        @command = ( 'ssh', '-F', $sshcfg, 'default', $cmd );
    } else {
        @command = ( 'vagrant', 'ssh', '--command', $cmd, $name );
    }

    my $rc = system(@command);
    return $? >> 8;
}

=head2 Vagrant::backtick COMMAND [, NAME ]

Runs the given command on the Vagrant instance via SSH. The stdout from the
SSH session is returned.

=cut

sub backtick {
    my $cmd = shift;
    my $name = shift || 'default';

    my $command;

    if ( -f $sshcfg ) {
        $command = "ssh -F $sshcfg default \"$cmd\"";
    } else {
        $command = "vagrant ssh --command \"$cmd\" $name";
    }

    my $rc = `$command`;
    return $rc;
}

1;
