# INSTALL DEPENDENCIES

    cpanm --installdeps --with-develop .        # module dependencies
    cpm install -L local Test::JSON::Schema::Acceptance@1.040 YAML::XS YAML::PP Cpanel::JSON::XS JSON::XS
                                                # developer modules, kept out of the system perl
    PERL5LIB=local/lib/perl5 ACCEPTANCE_TESTING=1 prove -l t/acceptance.t
    cpanm Dist::Zilla                           # to build and upload module to cpan
    dzil authordeps --missing | cpanm           # to install dzil dependencies
    cpanm Pod::Weaver::Section::Contributors    # to automatically maintain the list of contributors
    apt-get install spell                       # for spell check

# SETUP

    dzil setup

# RUN TESTS

    prove -l t
    dzil test

# BUILD

    dzil build

# RELEASE/UPLOAD TO CPAN

    # update Changes
    # update version in JSONSchema::Validator
    dzil release
