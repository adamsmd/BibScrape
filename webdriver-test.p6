#!/usr/bin/env raku

# $ sudo apt install libperl-dev
# $ zef install Inline::Perl5

say "hello";

use lib:from<Perl5> 'dep/WebDriver-Tiny-0.102/lib/';
use WebDriver::Tiny:from<Perl5>;

# TODO: spawn('geckodriver')
# TODO: kill geckodriver on exit

my $drv = WebDriver::Tiny.new(port => 4444);

# Go to Google.
$drv.get('https://www.google.co.uk');

# Type into the search box 'p', 'e', 'r', 'l', <RETURN>.
$drv.find('input[name=q]').send_keys("perl\xe006"); #\N{WD_RETURN}");

sleep 1;

#print($drv->html);

# Click the first perl result (perl.org).
$drv.find(".r > a")[0].click;

# Save a screenshot of the page.
$drv.screenshot('/tmp/perl.org.png');

$drv._req( DELETE => "" );
$drv = Nil;
