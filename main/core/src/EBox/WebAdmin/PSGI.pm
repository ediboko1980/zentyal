# Copyright (C) 2010-2014 Zentyal S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use strict;
use warnings;

package EBox::WebAdmin::PSGI;

# Package: EBox::WebAdmin::PSGI
#
#    Package in charge of managing PSGI applications inside WebAdmin
#    PSGI application

use EBox::Config;
use EBox::Exceptions::DataExists;
use EBox::Exceptions::DataNotFound;
use EBox::Exceptions::Internal;

use File::Slurp;
use JSON::XS;

use constant WEBADMIN_DIR => EBox::Config::conf() . 'webadmin/';
use constant APPS_FILE => WEBADMIN_DIR . 'psgi-subapps.yaml';

my $_apps;

# Group: Public methods

# Procedure: addSubApp
#
#    Add a new sub PSGI app
#
# Parameters:
#
#    url - String the url to mount this app
#
#    appName - String the app name to get the code ref for PSGI app
#
#    sslValidation - Boolean to indicate whether it requires SSL validation
#                    *(Optional)* Default value: False
#
#    validateFunc - String the code to validate that SSL environment
#
# Exceptions:
#
#    <EBox::Exceptions::DataExists> - thrown if the url does already
#    exists
#
sub addSubApp
{
    my ($url, $appName, $sslValidation, $validateFunc) = @_;

    my $json = _read();
    if (exists $json->{$url}) {
        throw EBox::Exceptions::DataExists(data => 'url', value => $url);
    }
    $json->{$url} = { appName => $appName, sslValidation => $sslValidation,
                      validateFunc => $validateFunc };
    _write($json);
}

# Procedure: removeSubApp
#
#    Remove a sub PSGI app
#
# Parameters:
#
#    url - String the url to mount this app
#
# Exceptions:
#
#    <EBox::Exceptions::DataNotFound> - thrown if the url does not exist
#
sub removeSubApp
{
    my ($url) = @_;

    my $json = _read();
    unless (exists $json->{$url}) {
        throw EBox::Exceptions::DataNotFound(data => 'url', value => $url);
    }
    delete $json->{$url};
    _write($json);
}

# Function: subApps
#
# Returns:
#
#    Array ref - containing hash ref with the following keys:
#
#      - url: String the url to mount the app
#      - app: Code ref the PSGI app subroutine
#      - sslValidation - Boolean indicating if any SSL validation is required
#      - validate - Code ref
#
sub subApps
{
    my $json = _read();

    my @res;
    while (my ($url, $appConf) = each %{$json}) {
        my $validate = undef;
        if ($appConf->{sslValidation} and $appConf->{validateFunc}) {
            $validate = _getCodeRef($appConf->{validateFunc});
        }
        push(@res, {'url' => $url,
                    'app' => _getCodeRef($appConf->{appName}),
                    'sslValidation' => $appConf->{sslValidation},
                    'validate' => $validate})
    }
    $_apps = \@res;
    return \@res;
}

# Function: subApp
#
#   Get the sub app that match the criteria set
#
# Parameters:
#
#   url - String the url to check
#
#   sslValidation - Boolean the sub app with SSL validation. Default value: false
#
# Returns:
#
#    Hash ref - containing the following keys:
#
#      - url: String the url to mount the app
#      - app: Code ref the PSGI app subroutine
#      - user_id: String it is required validation, then the user_id used
#
#    Undef if not found
#
sub subApp
{
    my (%params) = @_;

    $params{sslValidation} = 0 unless (exists $params{sslValidation});
    my $apps = $_apps;
    unless ($apps and scalar(@{$apps}) > 0) {
        $apps = subApps();
    }
    my @matched = grep { my $url = $_->{url}; $params{url} =~ /^$url/ and $_->{sslValidation} == $params{sslValidation} }
      @{$apps};
    if (@matched) {
        return $matched[0];
    }
    return undef;
}

# Method: validate
#
#  Validate the given environment in an app
#
# Parameters:
#
#  app - Hash ref the sub-app returned by <subApp> or <subApps>
#
#  env - Hash ref the Plack environment
#
# Returns:
#
#  Boolean - indicating if we validate
#
sub validate
{
    my ($app, $env) = @_;

    my $validateSub = $app->{validate};
    return (&$validateSub($env));
}

# Group: Private methods

# Read the file
sub _read
{
    my ($json) = {};
    if (-e APPS_FILE) {
        ($json) = new JSON::XS->decode(File::Slurp::read_file(APPS_FILE));
    }
    return $json;
}

# Write the file
sub _write
{
    my ($json) = @_;

    unless (-d WEBADMIN_DIR) {
        mkdir(WEBADMIN_DIR);
    }
    File::Slurp::write_file(APPS_FILE, new JSON::XS->encode($json));
}

# Get the coderef
sub _getCodeRef
{
    my ($name) = @_;

    my @nameParts = split('::', $name);
    my $relativeName = pop(@nameParts);
    my $pkgName = join('::', @nameParts);
    eval "use $pkgName";
    if ($@) {
        throw EBox::Exceptions::Internal("Cannot load $pkgName: $@");
    }
    return UNIVERSAL::can($pkgName, $relativeName);

}

1;
