#include <stdint.h>
#include <stdio.h>
#include <climits>

#include <fuzzer/FuzzedDataProvider.h>
#include "gdcmSystem.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    FuzzedDataProvider provider(data, size);
    std::string astr = provider.ConsumeRandomLengthString();
    const char* a = astr.c_str();
    std::string bstr = provider.ConsumeRandomLengthString();
    const char* b = bstr.c_str();

    gdcm::System::StrCaseCmp(a, b);

    return 0;
}