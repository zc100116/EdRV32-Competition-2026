// File: gcc_load2.cc; Spec: C2-I2 exact load latency scheduling experiment.
// GCC 15.2 host plugin: use a two-cycle true dependency after integer loads.
// No code or ABI changes: only scheduler dependency cost is adjusted.
#include "gcc-plugin.h"
#include "rtl.h"
#include "target.h"
#include "insn-attr.h"

int plugin_is_GPL_compatible;
static int (*original_cost)(rtx_insn *, int, rtx_insn *, int, unsigned int);

static int load2_cost(rtx_insn *insn, int dep_type, rtx_insn *producer,
                      int cost, unsigned int strength)
{
    if (original_cost)
        cost = original_cost(insn, dep_type, producer, cost, strength);
    if (dep_type == REG_DEP_TRUE && INSN_P(producer) && get_attr_type(producer) == TYPE_LOAD)
        return 2;
    return cost;
}

int plugin_init(struct plugin_name_args *, struct plugin_gcc_version *)
{
    original_cost = targetm.sched.adjust_cost;
    targetm.sched.adjust_cost = load2_cost;
    return 0;
}
