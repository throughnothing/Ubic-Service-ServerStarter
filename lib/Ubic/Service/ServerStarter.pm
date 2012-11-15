use strict;
use warnings;
package Ubic::Service::ServerStarter;
use base qw(Ubic::Service::Skeleton);

use Params::Validate qw(:all);
use Plack;

use Ubic::Daemon qw(:all);

# ABSTRACT: Helper for running psgi applications with ubic and plackup

my $server_command = $ENV{'UBIC_SERVICE_SERVERSTARTER_BIN'} || 'start_server';

sub new {
    my ($class) = (shift);

    my $params = validate(@_, {
        app_name    => { type => SCALAR, optional => 1 },
        cmd         => { type => ARRAYREF },
        args        => { type => HASHREF, optional => 1 },
        user        => { type => SCALAR, optional => 1 },
        group       => { type => SCALAR | ARRAYREF, optional => 1 },
        status      => { type => CODEREF, optional => 1 },
        ubic_log    => { type => SCALAR, optional => 1 },
        env         => { type => HASHREF, optional => 1 },
        stdout      => { type => SCALAR, optional => 1 },
        stderr      => { type => SCALAR, optional => 1 },
        pidfile     => { type => SCALAR, optional => 1 },
        cwd         => { type => SCALAR, optional => 1 },
    });

    return bless $params => $class;
}

sub pidfile {
    my ($self) = @_;
    return $self->{pidfile} if defined $self->{pidfile};
    return "/tmp/$self->{app_name}.pid" if defined $self->{app_name};
    return "/tmp/".$self->full_name.".pid";
}

sub sspidfile {
    my ($self) = @_;
    return $self->{args}{'pid-file'} || $self->pidfile . '.ss';
}

sub statusfile {
    my ($self) = @_;
    return $self->{args}{'status-file'} || $self->pidfile . '.status.ss';
}

sub bin {
    my ($self) = @_;

    my @cmd = split(/\s+/, $server_command);

    my %args = %{ $self->{args} };
    $args{'pid-file'} = $self->sspidfile unless $args{'pid-file'};
    $args{'status-file'} = $self->statusfile unless $args{'status-file'};

    for my $key (keys %args) {
        my $cmd_key = (length $key == 1) ? '-' : '--';
        $cmd_key .= $key;
        my $v = $args{$key};
        next unless defined $v;
        push @cmd, $cmd_key, $v;
    }
    push @cmd, '--', @{ $self->{cmd} };

    return \@cmd;
}

sub start_impl {
    my ($self) = @_;

    my $daemon_opts = {
        bin => $self->bin,
        pidfile => $self->pidfile,
        term_timeout => 5, # TODO - configurable?
    };
    for (qw/ env cwd stdout stderr ubic_log /) {
        $daemon_opts->{$_} = $self->{$_} if defined $self->{$_};
    }
    start_daemon($daemon_opts);
    return;
}

sub stop_impl {
    my ($self) = @_;
    return stop_daemon($self->pidfile, { timeout => 7 });
}

sub status_impl {
    my ($self) = @_;
    my $running = check_daemon($self->pidfile);
    return 'not running' unless ($running);
    if ($self->{status}) {
        return $self->{status}->();
    } else {
        return 'running';
    }
}

sub reload {
    my ($self) = @_;
    system $server_command, '--restart',
        '--pid-file', $self->sspidfile,
        '--status-file', $self->statusfile;
    return 'reloaded';
}

sub user {
    my $self = shift;
    return $self->{user} if defined $self->{user};
    return $self->SUPER::user;
};

sub group {
    my $self = shift;
    my $groups = $self->{group};
    return $self->SUPER::group() if not defined $groups;
    return @$groups if ref $groups eq 'ARRAY';
    return $groups;
}

sub timeout_options {
    # TODO - make them customizable
    return {
        start => { trials => 15, step => 0.1 },
        stop => { trials => 15, step => 0.1 },
    };
}

sub defaults {
    return ();
}


1;

=head1 SYNOPSIS

    use Ubic::Service::ServerStarter;
    return Ubic::Service::ServerStarter->new({
        cmd => [
            'starman',
            '--preload-app',
            '--env' => 'development',
            '--workers' => 5,
        ],
        args => {
            interval => 5,
            port => 5003,
            signal-on-hup => 'QUIT',
            signal-on-term => 'QUIT',
        },
        ubic_log => '/var/log/app/ubic.log',
        stdout   => '/var/log/app/stdout.log',
        stderr   => '/var/log/app/stderr.log',
        user     => "www-data",
    });

=head1 DESCRIPTION

This service is a common ubic wrap for psgi applications.
It uses plackup for running these applications.

=head1 NAME

Ubic::Service::ServerStarter - ubic service class for running commands
with L<Server::Starter>

=head1 METHODS

=over

=item I<args> (optional)

Arguments to send to start_server.

=item I<cmd> (required)

ArrayRef of command + options to run with server starter.  Everything passed
here will go be put after the C<--> in the C<start_server> command:

    start_server [ args ] -- [ cmd ]

This argument is required becasue we have to have something to run!

=item I<status>

Coderef to special function, that will check status of your application.

=item I<ubic_log>

Path to ubic log.

=item I<stdout>

Path to stdout log of plackup.

=item I<stderr>

Path to stderr log of plackup.

=item I<user>

User under which plackup will be started.

=item I<group>

Group under which plackup will be started. Default is all user groups.

=item I<cwd>

Change working directory before starting a daemon.

=item I<pidfile>

Pidfile for C<Ubic::Daemon> module.

If not specified, it will be derived from service's name or from I<app_name>,
if provided.

Pidfile is:

=over

=item *

I<pidfile> option value, if provided;

=item *

C</tmp/APP_NAME.pid>, where APP_NAME is I<app_name> option value, if it's
provided;

=item *

C</tmp/SERVICE_NAME.pid>, where SERVICE_NAME is service's full name.

=item C<pidfile()>

Get pidfile name.

=item C<bin()>

Get command-line with all arguments in the arrayref form.

=for Pod::Coverage defaults

=back
