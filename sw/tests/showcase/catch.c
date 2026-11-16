/* catch.c — T-GAMES-MORE acceptance; basket speed cap, rim crossing and signed scores. */
#include "catch.h"
#include <assert.h>
#include <stdio.h>
int main(void)
{
    catch_state_t s;
    catch_init(&s,21);
    catch_input(&s,1000,true);
    catch_step(&s);
    assert(s.basket_x == 655*GAME_Q);
    for (unsigned i = 0; i < 40; ++i) catch_step(&s);
    assert(s.basket_x == 1000*GAME_Q);
    catch_input(&s,0,true);
    catch_step(&s);
    assert(s.basket_x == 985*GAME_Q && s.target_x == GAME_SAFE_LEFT*GAME_Q);
    catch_input(&s,1280,false);
    assert(s.target_x == GAME_SAFE_LEFT*GAME_Q);
    catch_init(&s,21);
    s.ticks = 2;
    s.fruit[0] = (catch_fruit_t){640*GAME_Q,539*GAME_Q,5*GAME_Q,0,true,false};
    s.fruit[1] = (catch_fruit_t){900*GAME_Q,539*GAME_Q,5*GAME_Q,0,true,false};
    catch_step(&s);
    assert(s.score == 10 && !s.fruit[0].active && s.fruit[1].active);
    catch_step(&s);
    assert(s.score == 10); /* Rim crossing is scored once. */
    s.fruit[0] = (catch_fruit_t){640*GAME_Q,539*GAME_Q,5*GAME_Q,0,true,true};
    catch_step(&s);
    assert(s.score == -20 && s.flash == CATCH_FLASH*GAME_SUBSTEPS);
    s.ticks = CATCH_SECONDS*GAME_STEP_HZ-1;
    catch_step(&s);
    assert(s.done);
    int before = s.basket_x;
    catch_input(&s,1000,true);
    catch_step(&s);
    assert(s.basket_x == before);
    for (unsigned speed = GAME_SLOW; speed <= GAME_FAST; ++speed) {
        catch_init(&s,21);
        s.speed = speed;
        catch_step(&s);
        assert(s.fruit[0].vy == CATCH_FALL_START*GAME_Q*(int)speed/4);
        for (unsigned t = 1; t < (CATCH_SPAWN*4/speed)*GAME_SUBSTEPS; ++t) catch_step(&s);
        assert(!s.fruit[1].active);
        catch_step(&s);
        assert(s.fruit[1].active);
    }
    puts("PASS catch: x-only tracking, 900 px/s limit, range clamp, absent hand, "
         "rim crossing/miss, fruit/bomb scores, flash and 60-second end");
}
