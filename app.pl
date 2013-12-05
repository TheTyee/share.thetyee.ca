#!/usr/bin/env perl
use Modern::Perl '2013';
use Mojolicious::Lite;
use Mojo::Util qw(quote url_escape);
use Shares::Schema;
use Data::Dumper;
use Try::Tiny;
use Email::Valid;
use Regexp::Common qw /profanity/;
use HTML::Entities;

plugin JSONP => callback => 'cb';
my $config = plugin 'JSONConfig';

# Get a UserAgent
my $ua = Mojo::UserAgent->new;

# WhatCounts config
my $API        = $config->{'wc_api_url'};
my $wc_list_id = $config->{'wc_listid'};
my $wc_realm   = $config->{'wc_realm'};
my $wc_pw      = $config->{'wc_password'};

# Validation helpers
helper check_emails => sub {
    my $self           = shift;
    my $recipients_str = shift;
    my $sender_str     = shift;
    my @emails         = $self->split_emails( $recipients_str );
    push @emails, $sender_str;
    my @results;
    if ( @emails >= 10 ) { # Limit to 10 messages
        push @results, "Only 10 messages can be sent at a time.";
        return @results;
    }
    for my $addr ( @emails ) {
        my $r = Email::Valid->address( $addr );
        unless ( $r ) {
            push @results,
                "$addr doesn't look like a properly formatted e-mail address.";
        }
    }
    return @results;
};

helper check_message_content => sub {
    my $self    = shift;
    my $message = shift;
    my @results;
    if ( lc( $message ) =~ /$RE{profanity}/ ) {
        push @results, 'Your message appears to contain profanity. Feel free to revise.';
    };
    if ( $message eq '' ) {
        push @results, 'Message appears to contain no content';
    };
    if ( length( $message ) >= 1024 ) {
        push @results, 'Message is too long. Please keep it concise!'
    };
    return @results;
};

# Data preparation helpers
helper prepare_recipients => sub {
    my $self           = shift;
    my $recipients_str = shift;
    my $sender_str     = shift;
    my @emails         = $self->split_emails( $recipients_str );
    my @messages = map { email_to => trim( $_ ), email_from => $sender_str },
        @emails;
    return \@messages;
};

helper prepare_events => sub {
    my $self     = shift;
    my $messages = shift;    # the individual messages to send
    my $event    = shift;    # the share
    my $events   = [];
    for my $message ( @$messages ) {
        my $e = { %{$event} };    # Make a copy of the event
        $e->{'email_to'} = $message->{'email_to'};
        push $events, $e;
    }
    return $events;
};

# Utilities
helper split_emails => sub {
    my $self           = shift;
    my $recipients_str = shift;
    my @emails;
    if ( $recipients_str =~ /(,\w?)/g ) {
        @emails = split( ',', $recipients_str );
    }
    elsif ( $recipients_str =~ /\n/ ) {
        @emails = split( '\n', $recipients_str );
    } else {
        push @emails, $recipients_str;
    }
    return @emails;
};

sub trim {
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

# Database helpers
helper dbh => sub {
    my $schema = Shares::Schema->connect( $config->{'pg_dsn'},
        $config->{'pg_user'}, $config->{'pg_pass'}, );
    return $schema;
};

helper find_or_new => sub {
    my $self  = shift;
    my $event = shift;
    my $dbh   = $self->dbh();
    my $result;
    try {
        $result = $dbh->txn_do(
            sub {
                my $rs = $dbh->resultset( 'Event' )->find_or_new( {%$event} );
                #$self->app->log->debug( Dumper( $rs ) );
                unless ( $rs->in_storage ) {
                    $rs->insert;
                }
                return $rs;
            }
        );
    }
    catch {
        $self->app->log->debug( "Caught error: " . $_ );
        return;
    };
    return $result;
};

# Send message event via WhatCounts
helper send_message => sub {
    my $self   = shift;
    my $record = shift;
    $self->stash( event => $record );
    my %wc_args = (
        r       => $wc_realm,
        p       => $wc_pw,
        c       => 'send',
        list_id => $wc_list_id,
        format  => 99,
    );
    my $result;
    my $to          = $record->email_to;
    my $from        = $record->email_from;
    my $from_quoted = quote $record->email_from;
    my $title       = quote $record->title;
    my $url         = quote $record->url;
    my $image       = quote $record->img;
    my $summary     = quote $record->summary;
    my $message     = quote encode_entities( $record->message, '\n' );
    my $id          = $record->id;
    if ( $record->wc_result_send )
    {    # Already have a result for this record. Previously sent
        return "This story and message to $to was previously sent by $from";
    }
    #$self->app->log->debug( $record->email_to );
    my $message_args = {
        %wc_args,
        to               => $to,
        from             => $from,
        reply_to_address => $from,
        errors_to        => $from,
        template_id      => '132665',
        charset          => 'ISO-8859-1',
        data =>
            "from,title,url,image,summary,message^$from_quoted,$title,$url,$image,$summary,$message"
    };
    # Get the subscriber record, if there is one already
    my $s = $ua->post( $API => form => $message_args );
    if ( my $res = $s->success ) {
        $result = $res->body;
    }
    else {
        my ( $err, $code ) = $s->error;
        $result = $code ? "$code response: $err" : "Connection error: $err";
    }
    $record->wc_result_send( $result );
    $record->update;

    #$self->app->log->debug( $result );
    return $result;
};

get '/' => sub {
    my $self   = shift;
    $self->render( text => 'share.thetyee.ca' );
};

get '/send' => sub {
    my $self         = shift;
    my $errors       = [];
    my $params       = $self->req->params->to_hash;
    my $url          = $params->{'url'};
    my $title        = $params->{'title'};
    $title           =~ s/The Tyee – //g;
    my $summary      = $params->{'summary'};
    my $img          = $params->{'img'};
    my $message      = $params->{'message'};
    my $email_to     = $params->{'email_to'};
    my $email_from   = $params->{'email_from'};
    my $wc_sub_pref  = $params->{'wc_sub_pref'};
    my $share_params = {
        url         => $url,
        title       => $title,
        summary     => $summary,
        img         => $img,
        message     => $message,
        email_from  => $email_from,
        wc_sub_pref => $wc_sub_pref,
    };
    push $errors, 'Missing a selection for subscription preference.' if !$wc_sub_pref;
    push $errors, $self->check_emails( $email_to, $email_from );
    push $errors, $self->check_message_content( $message );
    my $send_results = [];
    if ( !@$errors ) {
        my $messages = $self->prepare_recipients( $email_to, $email_from );
        my $events = $self->prepare_events( $messages, $share_params );
        my $results = [];
        for my $event ( @$events ) {
            my $result = $self->find_or_new( $event );
            push $results, $result;
        }
        for my $result ( @$results ) {
            my $send_result = $self->send_message( $result );
            push $send_results, $send_result;
        }
    }
    $self->stash(
        share_params => $share_params,
        send_results => $send_results,
        errors       => $errors,
    );
    $self->respond_to(
        json => sub {
            $self->render_jsonp(
                { result => $send_results, errors => $errors } );
        },
        html => { template => 'index' },
        any  => { text     => '', status => 204 }
    );
};
app->secret( $config->{'app_secret'} );
app->start;
__DATA__
