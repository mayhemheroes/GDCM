FROM --platform=linux/amd64 ubuntu:22.04 as builder

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake libxml2-dev
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y clang

COPY . /repo
WORKDIR /repo/build
RUN cmake .. -DGDCM_BUILD_APPLICATIONS=ON -DGDCM_USE_SYSTEM_LIBXML2=ON -DCMAKE_INSTALL_PREFIX=/install
RUN make -j8
RUN make install
RUN clang++ /repo/mayhem/fuzz_StrCaseCmp.cpp -fsanitize=fuzzer,address -I /install/include/gdcm-3.1/ -L /install/lib/ -lgdcmCommon -o /fuzz

FROM ubuntu:22.04 as package
COPY --from=builder /install /install
COPY --from=builder /fuzz /fuzz_StrCaseCmp
