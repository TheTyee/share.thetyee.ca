#!/usr/bin/env perl

use Shares::Schema;

use Modern::Perl '2013';
use Mojolicious::Lite;
use Mojo::UserAgent;
use utf8::all;
use Try::Tiny;
use Data::Dumper;

# Get the configuration
my $mode = $ARGV[0];
my $config = plugin 'JSONConfig' => { file => "../app.$mode.json" };

# Get a UserAgent
my $ua = Mojo::UserAgent->new;

# WhatCounts setup
my $API        = $config->{'wc_api_url'};
my $wc_list_id = $config->{'wc_sub_listid'};
my $wc_realm   = $config->{'wc_realm'};
my $wc_pw      = $config->{'wc_password'};

main();


#-------------------------------------------------------------------------------
#  Subroutines
#-------------------------------------------------------------------------------
sub main {
    my $dbh     = _dbh();
    my $records = _get_records( $dbh );
    _process_records( $records );
}

sub _get_records
{    # Get only records that have not been processed from the database
    my $schema     = shift;
    my $to_process = $schema->resultset( 'Event' )
        ->search( {
                wc_status => [ { '!=', '1' }, { '=', undef } ],
                #wc_status => { '=', undef }
            } );
    return $to_process;
}

sub _process_records {    # Process each record
    my $to_process = shift;
    while ( my $record = $to_process->next ) {
        my $wc_response;

        # Check each for a subscription request
        my $frequency = _determine_frequency( $record->wc_sub_pref );
        if ( $frequency ) {    # A subscription request
                               # Process the request
            $wc_response = _create_or_update( $record, $frequency );
            $record->wc_result_sub( $wc_response );
            if ( $record->wc_result_sub =~ /^\d+$/ )
            {                  # We got back a subscriber ID, so we're good.
                               # Now mark the record as processed
                $record->wc_status( 1 );
            }
        }
        else { # No subscription requested, so just mark processed and move on
            $record->wc_result_sub( 'None requested' );
            $record->wc_status( 1 );
        }

        # Commit the update
        $record->update;
    }
}

sub _dbh {
    my $schema = Shares::Schema->connect( $config->{'pg_dsn'},
        $config->{'pg_user'}, $config->{'pg_pass'}, );
    return $schema;
}

sub _determine_frequency
{    # Niave way to determine the subscription preference, if any
    my $subscription = shift;
    my $frequency;
    if ( $subscription =~ /weekly/i ) {
        $frequency = 'custom_pref_enews_weekly';
    }
    elsif ( $subscription =~ /daily/i ) {
        $frequency = 'custom_pref_enews_daily';
    }

    # Return undefined for no frequency selection (thus, no subscription)
    return $frequency;
}

sub _create_or_update {   # Post the vitals to WhatCounts, return the resposne
    my $record          = shift;
    my $frequency       = shift;
    my $email           = $record->email_from;
    my $date            = $record->timestamp;
    my $search;
    my $result;
    my %args = (
        r => $wc_realm,
        p => $wc_pw,
        format => '2',
    );
    my $search_args = {
        %args,
        cmd   => 'find',
        email => $email,
    };

    # Get the subscriber record, if there is one already
    my $s = $ua->post( $API => form => $search_args );
    if ( my $res = $s->success ) {
        $search = $res->body;
    }
    else {
        my ( $err, $code ) = $s->error;
        $result = $code ? "$code response: $err" : "Connection error: $err";
    }
    my $update_or_sub = {
        %args,
        # If we found a subscriber, it's an update, if not a subscribe
        cmd => $search ? 'update' : 'sub',
        list_id => $wc_list_id,
        #override_confirmation => '1',  # Removed to require double opt-in, Jan 2018
        #force_sub => '1',              # Removed to require double opt-in, Jan 2018
        data =>
            "email,custom_share_import,$frequency,custom_share_sub_date,custom_pref_tyeenews_casl,custom_pref_sponsor_casl^$email,1,1,$date,1,1"
    };
    my $tx = $ua->post( $API => form => $update_or_sub );
    if ( my $res = $tx->success ) {
        $result = $res->body;
    }
    else {
        my ( $err, $code ) = $tx->error;
        $result = $code ? "$code response: $err" : "Connection error: $err";
    }

# For some reason, WhatCounts doesn't return the subscriber ID on creation, so we search again.
    if ( $result =~ /SUCCESS/ ) {
        my $r = $ua->post( $API => form => $search_args );
        if ( my $res = $r->success ) { $result = $res->body }
        else {
            my ( $err, $code ) = $r->error;
            $result
                = $code ? "$code response: $err" : "Connection error: $err";
        }
    }

    # Just the subscriber ID please!
    $result =~ s/^(?<subscriber_id>\d+?)\s.*/$+{'subscriber_id'}/gi;
    chomp( $result );
    return $result;
}
