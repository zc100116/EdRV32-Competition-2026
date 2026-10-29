# B3V routing failure evidence

Confirmed: Route-2014 cannot route GND to OSHIFTIN0/1 of IOLHR_16_678/702/726/750 (8 loads). Total nets 80380, routed 80379. Route-0038 and Route-0008 terminate PnR.

fail_route_nets.txt is a 5.9 MB vendor diagnostic report, not a raw execution log. It retains all 18332 GND loads and the route tree so Claude can inspect local constant routing. The identically named companion diagnostic fail_st_const_route_nets.txt_all_nets.txt is not additionally copied. Database files remain local.

mt_route_fail_net_loads.txt gives the exact 8 failed loads. routing_progress.txt records convergence to 1 remaining net. Native PRR and port placement are under ../native_reports/place_route/.

Candidate source: 4 TMDS slave serializers each tie OSHIFTIN0/1 to 0, in DDR10TO1 mode with OCASCADE_EN=TRUE. Their relation to the failed physical cells remains a hypothesis until physical-to-logical mapping is established. DDR PHY also uses OSHIFTIN ports. No RTL/IP/constraint fix has been made or tested.
