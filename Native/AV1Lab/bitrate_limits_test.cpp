#include "bitrate_limits.h"

static_assert(CodecBudget::ValidFps(72));
static_assert(CodecBudget::ValidFps(90));
static_assert(CodecBudget::ValidFps(120));
static_assert(!CodecBudget::ValidFps(71));
static_assert(CodecBudget::Valid(1000000,1000000));
static_assert(CodecBudget::Valid(200000001,230000001));
static_assert(CodecBudget::Valid(500000000,500000000));
static_assert(!CodecBudget::Valid(999999,1000000));
static_assert(!CodecBudget::Valid(500000001,500000001));
static_assert(!CodecBudget::Valid(500000000,500000001));
static_assert(!CodecBudget::Valid(500000000,499999999));
static_assert(CodecBudget::Av1Level(480000000)==17);
static_assert(CodecBudget::Av1Level(480000001)==18);
static_assert(CodecBudget::Av1Level(500000000)==18);
static_assert(!CodecBudget::Av1LevelSupports(17,500000000));
static_assert(CodecBudget::Av1LevelSupports(18,500000000));
static_assert(CodecBudget::Av1LevelSupports(24,500000000));
int main() { return 0; }
