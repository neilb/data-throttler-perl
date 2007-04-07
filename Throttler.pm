###########################################
package Data::Throttler;
###########################################
use strict;
use warnings;
use Log::Log4perl qw(:easy);
use Set::IntSpan;
use Text::ASCIITable;

our $VERSION = "0.01";

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        %options,
    };

    bless $self, $class;
    $self->reset();

    return $self;
}

###########################################
sub reset {
###########################################
    my($self) = @_;

    if(!$self->{max_items} or
       !$self->{interval}) {
        LOGDIE "Both max_items and interval need to be defined";
    }

    if(!$self->{nof_buckets}) {
        $self->{nof_buckets} = 10;
    }

    if($self->{nof_buckets} > $self->{interval}) {
        $self->{nof_buckets} = $self->{interval};
    }

    $self->{buckets} = [];
    my $bucket_time_span = int ($self->{interval} / $self->{nof_buckets});

    $self->{bucket_time_span} = $bucket_time_span;

    my $time_start = time() -
        ($self->{nof_buckets}-1) * $bucket_time_span;

    for(1..$self->{nof_buckets}) {
        my $time_end = $time_start + $bucket_time_span - 1;
        push @{$self->{buckets}}, { 
            time  => Set::IntSpan->new("$time_start-$time_end"),
            count => {},
        };
        $time_start = $time_end + 1;
    }
}

###########################################
sub try_item {
###########################################
    my($self, %options) = @_;

    my $key = "_default";
    $key = $options{key} if defined $options{key};

    my $time = time();
    $time = $options{time} if defined $options{time};

    my $count = 1;
    $count = $options{count} if defined $options{count};

    foreach my $b (reverse @{$self->{buckets}}) {
        next unless $b->{time}->member($time);
        if(defined $b->{count}->{$key} and
           $b->{count}->{$key} == $self->{max_items}) {
            return 0;
        } else {
            $b->{count}->{$key} += $count;
            return 1;
        }
    }

    LOGDIE "We shouldn't be here ($key $time $count)";
}

###########################################
sub buckets_dump {
###########################################
    my($self) = @_;

    my $t = Text::ASCIITable->new();
    $t->setCols("Time", "Key", "Count");

    foreach my $b (@{$self->{buckets}}) {
        my $span = hms($b->{time}->min) . " - " . hms($b->{time}->max);

        if(! scalar keys %{$b->{count}}) {
            $t->addRow($span, "", "");
        }

        foreach my $key (sort keys %{$b->{count}}) {
            $t->addRow($span, $key, $b->{count}->{$key});
            $span = "";
        }
    }
    return $t->draw();
}

###########################################
sub hms {
###########################################
    my($time) = @_;

    my ($sec,$min,$hour) = localtime($time);
    return sprintf "%02d:%02d:%02d", 
           $hour, $min, $sec;
}

1;

__END__

=head1 NAME

Data::Throttler - Limit data throughput

=head1 SYNOPSIS

    use Data::Throttler;

    ### Simple: Limit throughput to 100 per hour

    my $throttler = Data::Throttler->new(
        max_items => 100,
        interval  => 3600,
    );

    if($throttler->try_item()) {
        print "Item can be pushed\n";
    } else {
        print "Item needs to wait\n";
    }

    ### Advanced: Use a persistent data store and throttle by key:

    my $throttler = Data::Throttler->new(
        max_items => 100,
        interval  => 3600,
        db_file   => "/tmp/mythrottle.dat",
    );

    if($throttler->try_item(key => "somekey")) {
        print "Item can be pushed\n";
    }

=head1 DESCRIPTION

C<Data::Throttler> helps solving throttling tasks like "allow a single
IP only to send 100 emails per hour". It provides an optionally persistent
data store to keep track of what happened before and offers a simple
yes/no interface to an application, which can then focus on performing
the actual task (like sending email) or suppressing/postponing it.

When defining a throttler, you can tell it to keep its
internal data structures in memory:

      # in-memory throttler
    my $throttler = Data::Throttler->new(
        max_items => 100,
        interval  => 3600,
    );

However, if the data structures need to be maintained across different
invokations of a script or several instances of scripts using the
throttler, using a persistent database is required:

      # persistent throttler
    my $throttler = Data::Throttler->new(
        max_items => 100,
        interval  => 3600,
        db_file   => "/tmp/mythrottle.dat",
    );

In the simplest case, C<Data::Throttler> just keeps track of single 
events. It allows a certain number of events per time frame to succeed
and it recommends to block the rest:

    if($throttler->try_item()) {
        print "Item can be pushed\n";
    } else {
        print "Item needs to wait\n";
    }

When throttling different categories of items, like attempts to send
emails by IP address of the sender, a key can be used:

    if($throttler->try_item( key => "192.168.0.1" )) {
        print "Item can be pushed\n";
    } else {
        print "Item needs to wait\n";
    }

In this case, each key will be tracked seperately, even if the quota
for one key is maxed out, other keys will still succeed until their
quota is reached.

=head2 HOW IT WORKS

To keep track of what happened within the specified time frame, 
C<Data::Throttler> maintains a round-robin data store, either in 
memory or on disk. It splits up the controlled time interval into
buckets and maintains counters in each bucket:

    1 hour ago                     Now
      +-----------------------------+
      | 3  | 7  | 0  | 0  | 4  | 1  |
      +-----------------------------+
       4:10 4:20 4:30 4:40 4:50 5:00

To decide whether to allow a new event to happen or not, C<Data::Throttler>
adds up all counters (3+7+4+1 = 15) and then compares the result 
to the defined threshold. If the event is allowed, the corresponding 
counter is increased:

    1 hour ago                     Now
      +-----------------------------+
      | 3  | 7  | 0  | 0  | 4  | 2  |
      +-----------------------------+
       4:10 4:20 4:30 4:40 4:50 5:00

While time progresses, old buckets are expired and then reused
for new data. 10 minutes later, the bucket layout would look like this:

    1 hour ago                     Now
      +-----------------------------+
      | 7  | 0  | 0  | 4  | 2  | 0  |
      +-----------------------------+
       4:20 4:30 4:40 4:50 5:00 5:10

=head2 ADVANCED USAGE

By default, C<Data::Throttler> will decide on the number of buckets by 
dividing the time interval by 10. It won't handle sub-seconds, though,
so if the time interval is less then 10 seconds, the number of buckets
will be equal to the number of seconds in the time interval.

If the default bucket allocation is unsatisfactory, you can specify 
it yourself:

    my $throttler = Data::Throttler->new(
        max_items   => 100,
        interval    => 3600,
        nof_buckets => 42,
    );

Mainly for debugging and testing purposes, you can specify a different
time than I<now> when trying to push an item:

    if($throttler->try_item(
          key  => "somekey",
          time => time() - 600 )) {
        print "Item can be pushed in the past\n";
    }

Speaking of debugging, there's a utility method C<buckets_dump> which
returns a string containing a formatted representation of what's in
each bucket. So the code

    use Throttler;
    
    my $throttler = Data::Throttler->new(
        interval  => 3600,
        max_items => 10,
    );

    $throttler->try_item(key => "foobar");
    $throttler->try_item(key => "foobar");
    $throttler->try_item(key => "barfoo");
    print $throttler->buckets_dump();

will print out something like

    .---------------------+--------+-------.
    | Time                | Key    | Count |
    |=--------------------+--------+------=|
    | 11:05:54 - 11:11:53 |        |       |
    | 11:11:54 - 11:17:53 |        |       |
    | 11:17:54 - 11:23:53 |        |       |
    | 11:23:54 - 11:29:53 |        |       |
    | 11:29:54 - 11:35:53 |        |       |
    | 11:35:54 - 11:41:53 |        |       |
    | 11:41:54 - 11:47:53 |        |       |
    | 11:47:54 - 11:53:53 |        |       |
    | 11:53:54 - 11:59:53 |        |       |
    | 11:59:54 - 12:05:53 | barfoo |     1 |
    |                     | foobar |     2 |
    '---------------------+--------+-------'

and allow for further investigation.

=head1 LEGALESE

Copyright 2007 by Mike Schilli, all rights reserved.
This program is free software, you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 AUTHOR

2007, Mike Schilli <cpan@perlmeister.com>