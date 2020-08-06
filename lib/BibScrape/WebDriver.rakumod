unit module BibScrape::WebDriver;

use variables :D;

use Temp::Path;
use File::Directory::Tree;

########

class WebDriver {
  has #`(Inline::Python::PythonObject:_) Any:_ $!web-driver handles *;
  has #`(Inline::Python:_) Any:_ $!python;
  has IO::Path:_ $downloads;

  method get(Str:D $url --> Any:U) {
    $!web-driver.get($url);
    return;
  }

  submethod BUILD(Bool:D :$show-window --> Any:U) {
    use variables :_; # Otherwise we get: Cannot find method '!highwater' on object of type FakeOfType
    require Inline::Python; # Must be the last import (otherwise we get: Cannot find method 'EXISTS-KEY' on 'BOOTHash': no method cache and no .^find_method)

    $!downloads = make-temp-dir:prefix<BibScrape->;
    $!python = Inline::Python.new;
    $!python.run(qq:to/END/);
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
        profile.set_preference('browser.download.folderList', 2) # Use a custom folder for downloading
        profile.set_preference('browser.download.dir', '$downloads')
        #profile.set_preference('permissions.default.image', 2) # Never load the images

        opt = options.Options()
        # Run without showing a browser window
        opt.headless = not $show-window

        return webdriver.Firefox(
          firefox_profile = profile,
          options = opt,
          service_log_path = '/dev/null')

      def select(element):
        return ui.Select(element)
      END
    $!web-driver = $!python.call('__main__', 'web_driver');
    return;
  }

  method close(--> Any:U) {
    $!web-driver.quit()
      if $!web-driver.defined;
    $!web-driver = Nil; #Inline::Python::PythonObject;
    $!python = Nil; #Inline::Python;
    rmtree $!downloads
      if $!downloads.defined;
    $!downloads = IO::Path;
  }

  method DESTROY(--> Any:U) { self.close(); }

  method meta(Str:D $name --> Str:D) is export {
    $!web-driver.find_element_by_css_selector( "meta[name=\"$name\"]" ).get_attribute( 'content' );
  }

  method metas(Str:D $name --> Array:D[Str:D]) is export {
    $!web-driver.find_elements_by_css_selector( "meta[name=\"$name\"]" )».get_attribute( 'content' );
  }

  method select(#`(Inline::Python::PythonObject:D) $element #`(--> Inline::Python::PythonObject:D)) is export {
    $!python.call( '__main__', 'select', $element);
  }

  method read-downloads(--> Str:D) is export {
    for 0..300 {
      my IO::Path:D @files = $!downloads.dir;
      return @files.head.slurp
        if @files;
      sleep 0.1;
    }
    die "Could not find downloaded file";
  }
}
########

sub infix:<%>(
    $obj where WebDriver:D | Any:D #`(Inline::Python::PythonObject:D),
    Str:D $attr
    --> Str:D) is export {
  $obj.__getattribute__($attr);
}

sub await(&block --> Any:D) is export {
  my Rat:D constant $timeout = 30.0;
  my Rat:D constant $sleep = 0.5;
  my Any:_ $result;
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
