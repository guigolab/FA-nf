FROM debian:stretch

# File Author / Maintainer
MAINTAINER Toni Hermoso Pulido <toni.hermoso@crg.eu>

# Adapted from https://github.com/CRG-CNAG/docker-debian-perlbrew

ARG PERLBREW_ROOT=/usr/local/perl
ARG PERL_VERSION=5.24.4
# Enable perl build options. Example: --build-arg PERL_BUILD="--thread --debug"
ARG PERL_BUILD=

# Base Perl and builddep
RUN set -x; \
apt-get update && apt-get upgrade; \
apt-get install -y perl bzip2 zip curl \
	build-essential
#RUN apt-get build-dep perl

RUN mkdir -p $PERLBREW_ROOT

RUN bash -c '\curl -L https://install.perlbrew.pl | bash'

ENV PATH $PERLBREW_ROOT/bin:$PATH
ENV PERLBREW_PATH $PERLBREW_ROOT/bin

RUN perlbrew install $PERL_BUILD perl-$PERL_VERSION
RUN perlbrew install-cpanm
RUN bash -c 'source $PERLBREW_ROOT/etc/bashrc'
		
ENV PERLBREW_ROOT $PERLBREW_ROOT
ENV PATH $PERLBREW_ROOT/perls/perl-$PERL_VERSION/bin:$PATH
ENV PERLBREW_PERL perl-$PERL_VERSION
ENV PERLBREW_MANPATH $PELRBREW_ROOT/perls/perl-$PERL_VERSION/man
ENV PERLBREW_SKIP_INIT 1

RUN ln -s $PELRBREW_ROOT/perls/perl-$PERL_VERSION/bin/perl /usr/local/bin/perl

# Specific of FA pipeline
RUN apt-get install -y r-base sqlite

# Perl packages
RUN cpanm Bio::SearchIO Bio::SeqIO Config::Simple DBI File::Basename Getopt::Long IO::Handle Lingua::EN::Ngram List::Util LWP::Simple LWP::UserAgent

# Clean cache
RUN apt-get clean
RUN set -x; rm -rf /var/lib/apt/lists/*

# Workdir place
RUN mkdir -p /project
WORKDIR /project


