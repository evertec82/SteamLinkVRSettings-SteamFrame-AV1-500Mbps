#pragma once
#include <stdint.h>

namespace CodecBudget {
constexpr uint32_t MaximumBps = 500000000u;
constexpr uint32_t Av1Level61MaximumBps = 480000000u;
constexpr bool Valid(uint32_t average, uint32_t peak) {
    return average >= 1000000u && average <= MaximumBps && peak >= average && peak <= MaximumBps;
}
// Explicit levels avoid NVENC AUTO emitting unconstrained level index 31.
constexpr uint32_t Av1Level(uint32_t peak) {
    return peak > Av1Level61MaximumBps ? 18u : 17u; // 6.2 or 6.1, high tier.
}
constexpr bool Av1LevelSupports(uint32_t level, uint32_t peak) {
    return peak <= Av1Level61MaximumBps || level == 18u || level == 24u;
}
}
