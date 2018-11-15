FROM biocorecrg/debian-perlbrew:stretch

# File Author / Maintainer
MAINTAINER Toni Hermoso Pulido <toni.hermoso@crg.eu>

RUN set -x ; apt-get update && apt-get -y upgrade

# Place /scripts
RUN mkdir -p /scripts

# Specific of FA pipeline
RUN apt-get install -y r-base sqlite mysql 
RUN apt-get install -y texlive-latex-base texlive-fonts-recommended texlive-fonts-extra texlive-latex-extra

# Perl packages
RUN cpanm Bio::SearchIO Bio::SearchIO::blastxml Bio::SeqIO Config::Simple Config::JSON DBI DBD:mysql DBD::SQLite File::Basename Getopt::Long IO::Handle JSON Lingua::EN::Ngram List::Util String::Util

RUN apt-get install -y libssl-dev

RUN cpanm IO::Socket::SSL LWP::Simple LWP::Protocol::https LWP::UserAgent

# Clean cache
RUN apt-get clean
RUN set -x; rm -rf /var/lib/apt/lists/*

ENV PATH /scripts:$PATH

COPY scripts/ /scripts/
RUN chmod -R a+rx /scripts/*


