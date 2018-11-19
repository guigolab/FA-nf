FROM biocorecrg/debian-perlbrew:stretch

# File Author / Maintainer
MAINTAINER Toni Hermoso Pulido <toni.hermoso@crg.eu>

RUN set -x ; apt-get update && apt-get -y upgrade

# Specific of FA pipeline
RUN apt-get install -y r-base sqlite mysql-client default-libmysqlclient-dev
RUN apt-get install -y texlive-latex-base texlive-fonts-recommended texlive-fonts-extra texlive-latex-extra

# Perl packages
RUN cpanm Bio::SearchIO Bio::SearchIO::blastxml Bio::SeqIO
RUN cpanm Config::Simple Config::JSON DBI DBD::mysql DBD::SQLite Digest::SHA File::Basename Getopt::Long IO::Handle JSON Lingua::EN::Ngram List::Util String::Util

RUN apt-get install -y libssl-dev

RUN cpanm IO::Socket::SSL LWP::Simple LWP::Protocol::https LWP::UserAgent

# Clean cache
RUN apt-get clean
RUN set -x; rm -rf /var/lib/apt/lists/*

# Place /scripts
RUN mkdir -p /scripts

ENV PATH /scripts:$PATH

COPY scripts/ /scripts/
RUN chmod -R a+rx /scripts/*


