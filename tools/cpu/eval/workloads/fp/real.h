/* real.h — C2-F workload precision selection; clock: host/target CPU. */
#include <math.h>
#ifdef SINGLE
 typedef float real_t;
 #define R(x) x##f
 #define rsqrt __builtin_sqrtf
 #define rsin sinf
 #define rcos cosf
 #define ratan atanf
 #define rlog logf
 #define rexp expf
#else
 typedef double real_t;
 #define R(x) x
 #define rsqrt __builtin_sqrt
 #define rsin sin
 #define rcos cos
 #define ratan atan
 #define rlog log
 #define rexp exp
#endif
extern void start_time(void);
extern void stop_time(void);
