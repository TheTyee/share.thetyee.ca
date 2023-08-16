#!/usr/bin/env perl

use Shares::Schema;

use Modern::Perl '2013';
use Mojolicious::Lite;
use Mojo::UserAgent;
use utf8::all;
use Try::Tiny;
use Data::Dumper;
use Digest::MD5 qw(md5 md5_hex md5_base64);


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
    say "getting records";
    my $schema     = shift;
    my $to_process = $schema->resultset( 'Event' )
        ->search( {
                wc_status => [ { '!=', '1' }, { '=', undef } ],
                #wc_status => { '=', undef }
            } );
        say "processing  $to_process";
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
 #           if ( $record->wc_result_sub =~ /^\d+$/ )
             if ( $record->wc_result_sub)  # as long as anything is there

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
    elsif ( $subscription =~ /national/i ) {
        $frequency = 'custom_pref_enews_national';
    }

    # Return undefined for no frequency selection (thus, no subscription)
    return $frequency;
}

sub _create_or_update {   # Post the vitals to WhatCounts, return the resposne
    my $record          = shift;
    my $frequency       = shift;
    my $email           = $record->email_from;
    
    
         my $lcemail    = lc $email;
   my $md5email = md5_hex ($lcemail); 
    
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

    
    
    
    
    my $ub = Mojo::UserAgent->new;

my $merge_fields = {
    APPEAL => "email_share_tool",
    P_T_CASL => 1
};


    
my $interests = {};

if ($frequency =~ /national/) { $interests -> {'34d456542c'} = \1 ; $merge_fields->{'P_S_CASL'} = 1; $interests -> {'5c17ad7674'} = \1 ; };
if ($frequency =~ /daily/)  { $interests -> {'e96d6919a3'} = \1 ; $merge_fields->{'P_S_CASL'} = 1; $interests -> {'5c17ad7674'} = \1 ;};
if ($frequency =~ /weekly/) {$interests -> {'7056e4ff8d'} = \1; $merge_fields->{'P_S_CASL'} = 1; $interests -> {'5c17ad7674'} = \1 ; };

$interests -> {'3f212bb109'} = \1 ; #tyee news
# $interests -> {'5c17ad7674'} = \1 ; # sponsor casl - not by default unless one above selected 

# add to both casl specila newsletter prefs by default
$email = lc $email;
my $errorText;
    # Post it to Mailchimp
    my $args = {
        email_address   => $email,
        status =>       => 'subscribed',
        status_if_new => 'subscribed',
        merge_fields => $merge_fields,
        interests => $interests
    };
    
        my $URL = Mojo::URL->new('https://Bryan:' . $config->{"mc_key"} . '@us14.api.mailchimp.com/3.0/lists/' . $config->{"mc_listid"} . '/members/' . $md5email);
    my $tx = $ua->put( $URL => json => $args );
    my $js = $tx->result->json;
     app->log->debug( "code" . $tx->res->code);
   app->log->debug( Dumper( $js));
   
 $ub->post($config->{'notify_url_2'} => json => {text => "email $email added via email share tool with result from mailchimp: " . Dumper($js) }) unless $email eq 'api@thetyee.ca'; 


# For some reason, WhatCountMAILCHIMPs doesn't return the subscriber ID on creation, so we search again.
 if ($tx->res->code == 200 )
   {     
   
        app->log->debug( "unique email id" .  $js->{'unique_email_id'});



    # Just the subscriber ID please!
   # $result =~ s/^(?<subscriber_id>\d+?)\s.*/$+{'subscriber_id'}/gi;
   # chomp( $result );
    $result = $tx->result->body;
        # Output response when debugging
      #          app->log->debug( Dumper( $tx  ) );
      #  app->log->debug( Dumper( $result ) );
            if ( $result =~ 'subscribed' ) {
            my $subscriberID = $js->{'unique_email_id'};
            return $subscriberID;
             }
        
    } else {
        my ( $err, $code ) = $tx->error;
        $result = $code ? "$code response: $err" : "Connection error: " . $err->{'message'};
        # TODO this needs to notify us of a problem
        app->log->debug( Dumper( $result ) );
        # Send a 500 back to the request, along with a helpful message
            $errorText = "error: "  . "status: " .  $js->{'status'} . " title: " .  $js->{'title'};
	app->log->info( $errorText) unless $email eq 'api@thetyee.ca';
            app->log->debug("error: "  . $errorText);
           return ($errorText);

    };
    
}
    
    
    
    
    
    
    
    
    
    