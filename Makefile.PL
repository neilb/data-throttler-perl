######################################################################
# Makefile.PL for Throttle
# 2007, Mike Schilli <cpan@perlmeister.com>
######################################################################
use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'         => 'Data::Throttler',
    'VERSION_FROM' => 'Throttler.pm', # finds $VERSION
    'PREREQ_PM'    => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Throttler.pm',
       AUTHOR     => 'Mike Schilli <cpan@perlmeister.com>') : ()),
);