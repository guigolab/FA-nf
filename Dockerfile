FROM biocorecrg/debian-perlbrew:stretch

# File Author / Maintainer
MAINTAINER Toni Hermoso Pulido <toni.hermoso@crg.eu>

RUN set -x ; apt-get update && apt-get -y upgrade

# Specific of FA pipeline
RUN apt-get install -y r-base sqlite mysql-client default-libmysqlclient-dev
RUN apt-get install -y texlive-latex-base texlive-fonts-recommended texlive-fonts-extra texlive-latex-extra

RUN apt-get install -y libxml2-dev libexpat1-dev libdb-dev libgd-dev

# Perl packages
RUN cpanm Config::Simple Config::JSON DBI DBD::mysql DBD::SQLite Digest::SHA File::Basename Getopt::Long IO::Handle JSON Lingua::EN::Ngram List::Util Scalar::Util String::Util

ARG BIOPERL_VERSION=1.7.5
RUN cpanm install CDRAUG/BioPerl-${BIOPERL_VERSION}.tar.gz
RUN cpanm Bio::SearchIO::blastxml

RUN apt-get install -y libssl-dev

RUN cpanm IO::Socket::SSL LWP::Simple LWP::Protocol::https LWP::UserAgent Text::Trim

# Install GFFread
RUN apt-get install -y git

ARG GCLIB_VERSION=v0.11.2
ARG GFFREAD_VERSION=v0.11.4

RUN git clone https://github.com/gpertea/gclib; cd gclib && git checkout ${GCLIB_VERSION}
RUN git clone https://github.com/gpertea/gffread; cd gffread && git checkout ${GFFREAD_VERSION}
RUN cd gffread; make release; mv gffread /usr/local/bin
RUN rm -rf gclib; rm -rf gffread

# Clean cache
RUN apt-get clean
RUN set -x; rm -rf /var/lib/apt/lists/*

# Place /scripts
RUN mkdir -p /scripts

ENV PATH /scripts:$PATH

COPY scripts/ /scripts/
RUN chmod -R a+rx /scripts/*


