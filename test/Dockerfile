FROM golang:latest as build

ADD main.go /
WORKDIR /
RUN go build -o app main.go

FROM cloud-apps-baser

ADD ./env.sh /env.sh
ADD ./certificates /certificates
ADD ./run.sh /run.sh
ADD . /test
COPY --from=build /app /app
