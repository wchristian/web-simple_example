#!/usr/bin/perl 

use strict;
use warnings;

use CGI::Carp qw(fatalsToBrowser);

use lib 'local/lib/perl5';
use lib 'libs';
use CMS::CustomerLogin;

use DB::Skip
  pkgs => [
    qw(
      Method::Generate::Constructor  Method::Generate::Accessor  Sub::Defer  Sub::Quote  warnings  Moo::_Utils  Web::Dispatch::ToApp  Class::Method::Modifiers
      Sub::Exporter::Util  Plack::Util::Accessor  Plack::Component
      )
  ],
  subs => [
    qw(
      Web::Simple::Application::_test_request_spec_to_http_request  Web::Dispatch::_to_try Web::Dispatch::Node::_curry
      Web::Dispatch::MAGIC_MIDDLEWARE_KEY  Web::Dispatch::_uplevel_middleware  Web::Dispatch::_redispatch_with_middleware
      )
  ];

use CMS::WebSimplePatch;

CMS::CustomerLogin->run_if_script;
