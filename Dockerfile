FROM ev3dev/ev3dev-jessie-ev3-base

RUN apt-get update; apt-get install -y cpanminus make gcc

RUN cpanm --installdeps Data::Debug Test::MockModule Net::Server CGI::Lite

RUN cpanm Data::Debug Test::MockModule Net::Server CGI::Lite

# docker build -t ev3dev .
# docker run -it --rm -v `pwd`:`pwd` -w `pwd` ev3dev bash
# docker run --rm -v `pwd`:`pwd` -w `pwd` -p 8080:8080 ev3dev perl bin/server.pl
# docker run --rm -v `pwd`:`pwd` -w `pwd` ev3dev prove -v t/server.t
