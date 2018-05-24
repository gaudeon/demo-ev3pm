FROM ev3dev/ev3dev-jessie-ev3-base

RUN apt-get update; apt-get install -y cpanminus make gcc

RUN cpanm --installdeps Data::Debug Test::MockModule Net::Server

RUN cpanm Data::Debug Test::MockModule Net::Server

# docker build -t ev3dev .
# docker run -it --rm -v `pwd`:`pwd` -w `pwd` ev3dev bash
