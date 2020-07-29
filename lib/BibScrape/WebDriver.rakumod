unit module BibScrape::WebDriver;

use Temp::Path;

########

our $web-driver is export;
my $python;
my IO::Path $downloads;

sub web-driver-open() is export {
  web-driver-close();

  use Inline::Python; # Must be the last import (otherwise we get: Cannot find method 'EXISTS-KEY' on 'BOOTHash': no method cache and no .^find_method)
  $downloads = make-temp-dir:prefix<BibScrape->;
  $python = Inline::Python.new;
  $python.run("
import os

from selenium import webdriver
from selenium.webdriver.common.desired_capabilities import DesiredCapabilities
from selenium.webdriver.firefox import firefox_profile
from selenium.webdriver.firefox import options
from selenium.webdriver.support import ui

def web_driver():
  profile = firefox_profile.FirefoxProfile()
  #profile.set_preference('browser.download.panel.shown', False)
  #profile.set_preference('browser.helperApps.neverAsk.openFile',
  #  'text/plain,text/x-bibtex,application/x-bibtex,application/x-research-info-systems')
  profile.set_preference('browser.helperApps.neverAsk.saveToDisk',
    'text/plain,text/x-bibtex,application/x-bibtex,application/x-research-info-systems')
  profile.set_preference('browser.download.folderList', 2)
  profile.set_preference('browser.download.dir', '$downloads')

  opt = options.Options()
  # Run without showing a browser window
  opt.headless = True

  return webdriver.Firefox(
    firefox_profile = profile,
    options = opt,
    service_log_path = '/dev/null')

def select(element):
  return ui.Select(element)
");
  $web-driver = $python.call('__main__', 'web_driver');
}

sub web-driver-close() is export {
  if $web-driver.defined {
    $web-driver.quit();
  }
  $web-driver = Any;
  $python = Any;
  $downloads = IO::Path;
}

END {
  web-driver-close();
}

########

sub infix:<%>($obj, Str $attr) is export { $obj.__getattribute__($attr); }

sub read-downloads is export {
  for 0..10 {
    my @files = $downloads.dir;
    if @files { return @files.head.slurp }
    sleep 0.1;
  }
  die "Could not find downloaded file";
}

sub select($element) is export {
  $python.call( '__main__', 'select', $element);
}

sub meta(Str $name --> Str) is export {
  $web-driver.find_element_by_css_selector( "meta[name=\"$name\"]" ).get_attribute( 'content' );
}

sub metas(Str $name --> Seq) is export {
  $web-driver.find_elements_by_css_selector( "meta[name=\"$name\"]" ).map({ .get_attribute( 'content' ) });
}

sub await(&block) is export {
  my constant $timeout = 30.0;
  my constant $sleep = 0.5;
  my $result;
  my $start = now.Num;
  while True {
    $result = &block();
    if $result { return $result }
    if now - $start > $timeout {
      die "Timeout while waiting for the browser"
    }
    sleep $sleep;
    CATCH { default { sleep $sleep; } }
  }
}
