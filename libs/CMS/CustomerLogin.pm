use strict;
use warnings;

package CMS::CustomerLogin;

use Moo;

extends 'CMS::Base';

use autodie;
use Try::Tiny;

use Plack::Middleware::Session;
use Plack::Session::Store::File;
use Plack::Request;

use Web::SimpleX::Helper::ActionWithRender 'action';
use Web::SimpleX::View::JSON qw( render_json view_error_json );
use Web::SimpleX::View::Template qw( render_template view_error_template process_template );

sub _build_config {
    our $config;
    require 'config/config.pl';
    return $config;
}

sub _build_db {
    my ( $self ) = @_;

    my $mysql = $self->config->{mysql};

    require DBIx::Simple;

    my $db = DBIx::Simple->new(
        "DBI:mysql:database=$mysql->{db};hostname=$mysql->{host};port=$mysql->{port}",    #
        $mysql->{user},
        $mysql->{pw},
        { mysql_enable_utf8 => 1 },
    );

    return $db;
}

sub dispatch_request {
    my ( $self, $env ) = @_;

    $self->req( Plack::Request->new( $env ) );

    (
        ''  => sub { Plack::Middleware::Session->new( store => $self->session_store ) },
        GET => sub {
            (
                '/'               => action( 'root_page' ),
                '/reset_password' => action( 'reset_password_form' ),
                '/price_list/*'   => action( 'price_list' ),

                '/passwort'        => auth_action( 'password_form' ),
                '/kundenkonto'     => auth_action( 'account_overview' ),
                '/dokumente'       => auth_action( 'documents_page' ),
                '/rechnungen'      => auth_action( 'bill_overview' ),
                '/produkte'        => auth_action( 'product_overview' ),
                '/logout'          => auth_action( 'handle_logout' ),
                '/welcome'         => auth_action( 'welcome_page' ),
                '/password_check'  => auth_action( 'password_check_form' ),
                '/zahlung'         => auth_action( 'payment_option_page' ),
                '/zahlungsdetails' => auth_action( 'payment_details' ),
                '/adressdaten'     => auth_action( 'adress_data' ),
                '/authorisierung'  => auth_action( 'partner_auth_form' ),
                '/newsletter'      => auth_action( 'newsletter_cfg_form' ),

                '/bestellen...' => ws_app( "CMS::CustomerLogin::Ordering" ),

                '/rechnungen/*' => auth_action( 'bill_download', 'download' ),
            );
        },
        POST => sub {
            (
                '/reset_password' => action( 'reset_password' ),

                '/login'           => action( 'handle_login',    'json' ),
                '/send_reset_code' => action( 'send_reset_code', 'json' ),

                '/bestellen/domains' => auth_action( 'domain_order_shortcut' ),

                '/zahlungsdetails' => auth_action( 'send_payment_detail_change', 'json' ),
                '/adressdaten'     => auth_action( 'adress_data_change',         'json' ),
                '/authorisierung'  => auth_action( 'send_partner_auth',          'json' ),
                '/newsletter'      => auth_action( 'set_newsletter_cfg',         'json' ),
                '/ticket'          => auth_action( 'send_new_ticket',            'json' ),

                '/bestellen...' => sub_dispatch(
                    '/upgrade'                     => auth_action( 'send_upgrade_order',  'json' ),
                    '/domains/send'                => auth_action( 'send_domain_order',   'json' ),
                    '/domains/add + %domain~&tld~' => auth_action( 'add_domain',          'json' ),
                    '/domains/delete + %domain~'   => auth_action( 'delete_domain',       'json' ),
                    '/domains/clear'               => auth_action( 'clear_domain_basket', 'json' ),
                ),

                '/get_phone_pass' => double_auth_action( 'get_phone_pass', 'json' ),
                '/passwort'       => double_auth_action( 'set_password',   'json' ),
            );
        },
        '' => action( 'error_404' ),
    );
}

sub ws_app {
    my ( $class ) = @_;
    return sub {
        eval "require $class" or die $@;
        return $class->to_psgi_app;
    };
}

sub sub_dispatch {
    my @dispatch = @_;
    return sub { @dispatch };
}

sub action_error_json {
    my ( $self, $error ) = @_;

    warn $self->req->address . ": $error";

    return { error => "unknown" };
}

sub action_error_template {
    my ( $self, $error ) = @_;

    warn $self->req->address . ": $error";

    return [ "handle_uri_error.xml", {}, 500 ];
}

sub error_404 {
    my ( $self ) = @_;
    warn "DEBUG/NOTICE: handle_uri: " . $self->req->path_info . " isn't handled here\n" if ( DEBUG );
    return [ "index.xml", {}, 404 ];
}

sub root_page { ["index.xml"] }

sub auth_action {
    my ( $action, $view ) = @_;
    my $guard = sub {
        my ( $self, $real_view ) = @_;
        return "auth_failure_$real_view" if !$self->is_logged_in;
        return $action;
    };
    return action( $guard, $view );
}

sub auth_failure_template { $_[0]->redirect( '/' ) }
sub auth_failure_json { { error => "Zugriff verweigert." } }

sub double_auth_action {
    my ( $action, $view ) = @_;
    my $guard = sub {
        my ( $self, $real_view ) = @_;
        my $pw = $self->req->param( "password_check" );
        return "auth_failure_$real_view" if !$pw or !$self->servicepw_ok( $self->is_logged_in, $pw );
        return $action;
    };
    return auth_action( $guard, $view );
}

sub is_logged_in { $_[0]->req->session->{kdnr} }

sub redirect {
    my ( $self, $url ) = @_;
    my $res = Plack::Response->new;
    $res->redirect( $url );
    return $res;
}

### SUB Handling

sub send_new_ticket {
    my ( $self ) = @_;

    my $params   = $self->req->parameters;
    my $customer = $self->get_customer_data( $self->req->session->{kdnr} );

    my $mail_success = $self->send_email(
        "new_ticket",
        args     => { params => $params, customer => $customer },
        fallback => {
            To   => 'support@profihost.com',
            From => $customer->{email}
        }
    );

    return { success => "Ticket übermittelt!" };
}

sub newsletter_cfg_form {
    my ( $self ) = @_;

    my $customer = $self->get_customer_data( $self->req->session->{kdnr} );

    return [ "newsletter_cfg_form.xml", { customer => $customer } ];
}

1;
