use strict;
use warnings;
use ExtUtils::MakeMaker;
use Alien::ckdl;

WriteMakefile(
    DISTNAME         => 'Text-KDL-XS',
    NAME             => 'Text::KDL::XS',
    VERSION_FROM     => 'lib/Text/KDL/XS.pm',
    ABSTRACT_FROM    => 'lib/Text/KDL/XS.pm',
    AUTHOR           => 'Davenonymous <perl@davenonymous.com>',
    LICENSE          => 'perl_5',
    MIN_PERL_VERSION => '5.012',

    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '6.64',
        'Alien::ckdl'         => '0',
    },
    BUILD_REQUIRES => {
        'Alien::ckdl' => '0',
    },
    PREREQ_PM => {
        'Alien::ckdl' => '0',
        'XSLoader'    => '0',
    },
    TEST_REQUIRES => {
        'Test::More' => '0.88',
    },

    OBJECT => '$(O_FILES)',
    XS     => { 'XS.xs' => 'XS.c' },
    C      => [ 'XS.c' ],
    INC    => Alien::ckdl->cflags,
    LIBS   => [ Alien::ckdl->libs ],

    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            bugtracker => { web => 'https://github.com/Davenonymous/perl-kdl-xs/issues' },
            repository => {
                type => 'git',
                url  => 'https://github.com/Davenonymous/perl-kdl-xs.git',
                web  => 'https://github.com/Davenonymous/perl-kdl-xs',
            },
        },
        dynamic_config => 1,
    },
);
