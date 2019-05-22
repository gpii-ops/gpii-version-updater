FROM ruby:2.6-alpine

RUN apk add --no-cache \
    curl \
    docker \
    git \
    jq \
    openssh-client
RUN gem install bundler

WORKDIR /home/app
COPY \
    Gemfile \
    Gemfile.lock \
    ./
RUN mkdir -p vendor/bundle && bundle install --path vendor/bundle

COPY \
    LICENSE.txt \
    README.md \
    Rakefile \
    sync_images.rb \
    sync_images_wrapper \
    ./
# COPY treats directories differently /shrug
COPY \
    spec \
    ./spec
RUN chmod -R +rX * && chmod +x sync_images_wrapper

CMD ./sync_images_wrapper
