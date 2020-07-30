unit module BibScrape::WebDriver;

use Temp::Path;

########

our $web-driver is export; # TODO: class
my Any $python; # TODO: Our?
my IO::Path $downloads;

sub web-driver-open(--> Any:U) is export {
  web-driver-close();

  use Inline::Python; # Must be the last import (otherwise we get: Cannot find method 'EXISTS-KEY' on 'BOOTHash': no method cache and no .^find_method)
  $downloads = make-temp-dir:prefix<BibScrape->;
  $python = Inline::Python.new;
  $python.run(qq:to/END/);
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
    END
  $web-driver = $python.call('__main__', 'web_driver');
  return;
}

sub web-driver-close(--> Any:U) is export {
  $web-driver.quit()
    if $web-driver.defined;
  $web-driver = Any;
  $python = Any;
  $downloads = IO::Path;
  return;
}

END {
  web-driver-close();
}

########

sub infix:<%>(Any:D $obj, Str:D $attr --> Str:D) is export { $obj.__getattribute__($attr); }

sub select(Any:D $element --> Any:D) is export {
  $python.call( '__main__', 'select', $element);
}

sub meta(Str:D $name --> Str:D) is export {
  $web-driver.find_element_by_css_selector( "meta[name=\"$name\"]" ).get_attribute( 'content' );
}

sub metas(Str:D $name --> Array:D[Str:D]) is export {
  $web-driver.find_elements_by_css_selector( "meta[name=\"$name\"]" )».get_attribute( 'content' );
}

sub await(&block --> Any:D) is export {
  my Rat:D constant $timeout = 30.0;
  my Rat:D constant $sleep = 0.5;
  my Any $result;
  my Num:D $start = now.Num;
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

sub read-downloads(--> Str:D) is export {
  for 0..10 {
    my IO::Path:D @files = $downloads.dir;
    return @files.head.slurp
      if @files;
    sleep 0.1;
  }
  die "Could not find downloaded file";
}
