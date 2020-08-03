unit module BibScrape::CommandLine;

class Param {
  has Parameter:D $.parameter is required handles *;
  has Str:D $.name is required;
  has Any:_ $.default is required;
  has Pod::Block::Declarator:_ $.doc is required;
  method new(Parameter:D $parameter --> Param:D) {
    my Str:D $name = ($parameter.name ~~ /^ "{$parameter.sigil}{$parameter.twigil}" (.*) $/).[0].Str;
    my Any:_ $default = $parameter.default && ($parameter.default)();
    self.bless(parameter => $parameter, name => $name, default => $default, doc => $parameter.WHY);
  }
}

sub params(Sub:D $main--> List:D) {
  my Param:D @params;
  my Param:D %params;
  for $main.signature.params -> Parameter:D $parameter {
    my Param:D $param = Param.new($parameter);
    if $param.named {
      %params{$param.name} = $param;
    } else {
      push @params, $param;
    }
  }
  (@params, %params)
}

sub type-name(Any:U $type --> Str:D) {
  given $type {
    when Positional { type-name($type.of); }
    when IO::Path { 'File'; }
    default { $type.^name; }
  }
}

sub GENERATE-USAGE(Sub:D $main, |capture --> Str:D) is export {
  my Int:D constant $end-col = 80;
  my List:D $list = params($main);
  my Param:D @params = $list[0];
  my Param:D %params = $list[1];
  my Str:D $out = '';
  sub col(Int:D $col --> Any:U) {
    my Int:D $old-col = $out.split("\n")[*-1].chars;
    if $old-col > $col { $out ~= "\n"; $old-col = 0; }
    $out ~= ' ' x ($col - $old-col);
    return;
  }
  sub wrap(Int:D $start, Str:D $str is copy --> Any:U) {
    for $str.split( / ' ' * ';' ' '* / ) -> Str:D $paragraph is copy {
      $paragraph ~~ s:g/ ' '+ $//;
      if $paragraph eq '' {
        $out ~= "\n";
      } else {
        for $paragraph ~~ m:g/ (. ** {0..($end-col - $start)}) [ ' '+ | $ ] / -> Str:D(Match:D) $line {
          col($start);
          $out ~= $line;
        }
      }
    }
    return;
  }
  $out ~= "Usage:\n";
  $out ~= "  $*PROGRAM-NAME [options]";

  # TODO: %params
  for @params -> Param:D $param {
    $out ~= " <" ~ $param.name ~ ($param.type ~~ Positional ?? '> ...' !! '>');
  }

  wrap(0, $main.WHY.leading);

  for $main.signature.params -> Parameter:D $parameter {
    my Param:D $param = Param.new($parameter);
    with $param.doc and $param.doc.leading {
      wrap(0, $_);
    }
    if $param.named {
      $out ~= ' ' ~ $param.named_names.map({ '-' ~ ($_.chars > 1 ?? '-' !! '') ~ $_ }).join( '|' );
      given $param.type {
        when Bool { }
        when Positional { $out ~= "=<{type-name($param.type)}> ..."; }
        default { $out ~= "=<{type-name($param.type)}>"; }
      }
    } else {
      given $param.type {
        when Positional { $out ~= " <{$param.name}> ..."; }
        default { $out ~= " <{$param.name}>"; }
      }
    }
    # TODO: comma in list keyword flags
    if $param.default.defined {
      if $param.type ~~ Positional {
        wrap(28, "Default: {$param.default.map({ "'$_'" })}");
      } else {
        wrap(28, "Default: {$param.default}");
      }
    } else {
      $out ~= "\n";
    }
    $out ~= "\n";
    # if $param.type ~~ Enumeration {
    #   wrap(4, "<{type-name($param.type)}> = {$param.type.enums.keys.join(' | ')};");
    # }
    with $param.doc and $param.doc.trailing {
      wrap(4, $_);
    }
    $out ~= "\n";
  }
  wrap(0, $main.WHY.trailing);
  $out.chomp;
}

sub ARGS-TO-CAPTURE(Sub:D $main, @str-args is copy where { $_.all ~~ Str:D }--> Capture:D) is export {
  my List:D $params = params($main);
  my Param:D @params = $params[0];
  my Param:D %params = $params[1];
  my Bool:D $no-parse = False;
  my Int:D $positionals = 0;
  sub def(Param:D $param) {
    $param.default
      // ($param.type ~~ Positional
        ?? Array[$param.type.of].new()
        !! $param.type);
  }
  my Any:_ @args = @params.map(&def);
  my Any:_ %args = %params.map({ $_.key => def($_.value) });
  while @str-args {
    my Str:D $arg = shift @str-args;
    given $arg {
      # Bare '--'
      when !$no-parse & /^ '--' $/ { $no-parse = True; }
      # Keyword
      when !$no-parse & /^ '--' ('/'?) (<-[=]>+) (['=' (.*)]?) $/ {
        my Bool:D $polarity = ($0.chars == 0);
        my Str:D $name = $1.Str;
        # TODO: when $name eq ''
        my Param:D $param = %params{$name}; # TODO: Missing param name
        given $param.type {
          when Positional {
            my Str:D $value-str = $2.[0].Str;
            if $value-str eq '' {
              if $polarity {
                %args{$param.name} = Array[$param.type.of].new();
              } else {
                %args{$param.name} = def($param);
              }
            } else {
              # TODO: comma in field options
              my Any:D $value = ($param.type.of)($value-str);
              if $polarity {
                push %args{$param.name}, $value;
              } else {
                %args{$param.name} =
                  Array[$param.type.of](
                    %args{$param.name}.grep({ not ($_ eqv $value) }));
              }
            }
          }
          default {
            my Str:D $value-str =
              $2.chars > 0 ?? $2.[0].Str
                !! $param.type ~~ Bool ?? $polarity.Str
                !! @str-args.shift; # TODO: missing arg
            my Any:D $value =
              do if $param.type ~~ Bool {
                do given $value-str {
                  when m:i/ 'true' | 'y' | 'yes' | 'on' | '1' / { True }
                  when m:i/ 'false' | 'n' | 'no' | 'off' | '0' / { False }
                  default { die; }
                };
              } else {
                ($param.type)($value-str)
              };
            %args{$param.name} = $value;
          }
        }
      }
      # Positionals
      default {
        my Param:D $param = @params[$positionals];
        given $param.type {
          when Positional {
            push @args[$positionals], ($param.type.of)($arg);
            # NOTE: no `$positionals++`
          }
          default {
            @args[$positionals] = ($param.type)($arg);
            $positionals++;
          }
        }
      }
    }
  }
  %args{ '' } = True # Prevent the capture from matching in order to trigger the usage message
    if %args<help>;
  my Capture:D $capture = Capture.new(list => @args, hash => %args);
  $capture;
}
