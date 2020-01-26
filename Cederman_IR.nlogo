breed [provinces province]
breed [states state]
breed [borders border]

undirected-link-breed [control-links control-link] ; links a province to its state
directed-link-breed [fronts front] ; links from a state to another

states-own [predator? resources biggest-threat attacking-unprovoked?]
fronts-own [local-resources border-provinces attack? war? trust-score decrease-trust?] ; from the perspective of node end1

; provinces-own [capital isCapital?]
; Instead, just check if the state and province are on the same pspace

to setup
  clear-all
  ; create the provinces and states
;  set victory-ratio superiority-ratio
  ask patches [
    set pcolor white
;    sprout-provinces 1 [set shape "square" set color one-of remove red base-colors]
    sprout-provinces 1 [set shape "square" set color one-of remove red base-colors set size 1.0]
    sprout-states 1 [ set color black set shape "circle" set size 0.25]
  ]

  ; make color a different color from all neighbors
  ask provinces [
    while [member? color ([color] of provinces-on [neighbors4] of patch-here)] [
      set color one-of remove red base-colors
    ]
  ]

  ; set up the states, links, and provinces' labels
  ask states [
    ; make color of patch same as color of province
    ask patch-here [
      set pcolor [color] of one-of provinces-on self
    ]
    ; create edge between state and province, set province label to who-number of state
    create-control-links-with provinces-here
    ask control-link-neighbors [
      set label [who] of myself
      set label-color black
    ]
    ; create predators, set their colors to red; initialize resource amounts
    set predator? (random-float 1 < proportion-predators)
    ask states with [predator? = True] [set color red]
    set resources (random-normal initial-resource-mean initial-resource-std-dev)
    if (resources < 0) [set resources 0]
  ]
  ; create the initial fronts
  ask states[
    let neighbor-states ([one-of control-link-neighbors] of (provinces-on ([neighbors4] of one-of control-link-neighbors) ))
    set neighbor-states (states with [member? self neighbor-states]) ; turn from a list to an agentsset
    create-fronts-to neighbor-states [
      set attack? false
      set war? false
      set local-resources 0
      set hidden? true
    ]
  ]

  ask fronts [
    set border-provinces []
    ; adds capital province to border-provinces
    set border-provinces lput (one-of provinces-on [patch-here] of state [who] of end1) border-provinces
    set trust-score 0
    set decrease-trust? false
  ]

;  ask fronts [
;    foreach border-provinces [
;      z -> ask ([neighbors4] of z) [
;        if ([label] of self )
;      ]
;    ]
;  ]
  reset-ticks
end

to step
  go
end

to go
  recompute-fronts ; do we want to do this every tick or only after a state has taken over a new province?
  if defensive-alliances? [
    update-trust-score
  ]
  decide-attacks
  reallocate-resources ; its weird that this after decide-attacks
  perform-battles
  check-victories
  harvest ; when does this occur / is it before check-victories?
  ask fronts with [war?] [
    set color red
    set hidden? false]
  tick
  ; assuming harvest happens after we check for victory
end

to recompute-fronts
  ; note - use neighbors 4, von neumann
  ; creates fronts for new states
  ask states with [count my-out-fronts = 0 and count my-control-links = 1][
;    if (any? self with [count my-control-links = 1]) and any? self with [count my-out-fronts = 0][
;      ask (states-on self) [
        let neighbor-states ([one-of control-link-neighbors] of (provinces-on ([neighbors4] of one-of control-link-neighbors) ))
        set neighbor-states (states with [member? self neighbor-states]) ; turn from a list to an agentsset
        create-fronts-to neighbor-states [
          set attack? false
          set war? false
          set local-resources 0
          set hidden? true
        ]
    create-fronts-from neighbor-states [
      set attack? false
      set war? false
      set local-resources 0
      set hidden? true
    ]
  ]
end



to update-trust-score
  ask states [
    ask my-out-fronts [
      ifelse decrease-trust? = true [
        set trust-score (1 - 0.5) * trust-score + 0.5 * (-1000)
      ]
      [
        set trust-score (1 - 0.01) * trust-score + 0.01 * (1000)
      ]
    ]
    let biggest_threat [end2] of one-of my-out-fronts
    ask my-out-fronts [
      if trust-score < [trust-score] of front ([who] of myself) ([who] of biggest_threat) [
        set biggest_threat end2
      ]
    ]
    set biggest-threat [who] of biggest_threat
  ]
end

; all states determine who to attack
to decide-attacks
  let unprovoked-attacks []
  ask states [
    ; attack neighbors if at war with them
    let no-wars true
    ask my-out-fronts [
      if war? [
        set no-wars false
        set attack? true
      ]
    ]
    ; if state is a predator and not in any wars, consider attacking weakest neighbor
    let original-state who
    if predator? and no-wars [
      if count fronts = 0 [ stop ] ; should never happen
      ; why in-front-neighbors vs front-neighbors
      let weakest one-of (front-neighbors with-min [resources]) ; finds weakest neighbor, randomly picks if there were multiple
;      if weakest = nobody [
;        ask my-out-fronts [set hidden? false]
;        show self
;      ]

      if (([resources] of weakest = 0) or (resources / [resources] of weakest > superiority-ratio))[ ; if exceeds superiority ratio, attack
        ask (front original-state ([who] of weakest) ) [set attack? true]
        set unprovoked-attacks lput (front original-state ([who] of weakest)) unprovoked-attacks
        ask front ([who] of weakest) original-state [
          set decrease-trust? true
        ]
      ]
    ]
   ]
   if defensive-alliances? [
      alliance-attack unprovoked-attacks
   ]
end

to alliance-attack [attacks-list]
  foreach attacks-list [
    z -> if ([biggest-threat] of ([end2] of z) = [who] of ([end1] of z)) [
      ask states with [biggest-threat = [who] of ([end1] of z)] [
        ask my-out-fronts with [[who] of end2 = [who] of ([end1] of z)] [
          set war? true
        ]
      ]
    ]
  ]
end

to perform-battles
  ask fronts [
    ; if a state attacks along a front, set the front and the inverse front to be at war
    ; and deduct locally allocated resourcs from the state being attacked
    if attack? [
      set color red
      set war? true
;      set hidden? false
      ask (front ([who] of end2) ([who] of end1)) [
        set war? true
;        set hidden? false
        set local-resources (local-resources - (.05 * [local-resources] of myself))
        if (local-resources < 0) [set local-resources 0] ; I'm assuming you do this error checking?

        ; CAREFUL- DO WE ALSO WANT TO CHANGE THE OVERALL RESOURCES OF THE STATE?
        ; ask end1 [ set resources (resources - resources-destroyed) ]
        ; also, make sure end1 is correctly referring to the state being attacked
      ]
    ]
  ]
end

to recompute-all-fronts
  ask states [
    let currlabel who
    let neighbor-provinces []
    ask control-link-neighbors [
      ask provinces-on neighbors4 [
        if label != currlabel [;current-label [
          set neighbor-provinces lput self neighbor-provinces
        ]
      ]
    ]
    set neighbor-provinces (provinces with [member? self neighbor-provinces])
    let neighbor-states ([one-of control-link-neighbors] of neighbor-provinces)
    set neighbor-states (states with [member? self neighbor-states])

    ; Delete fronts where states are no longer neighbors
    ask my-out-fronts with [not member? end2 neighbor-states][die]
    ask my-in-fronts with [not member? end1 neighbor-states][die]

    ; Create fronts for states that are newly neighbors
    ask neighbor-states with [not member? self front-neighbors][
      create-front-to myself [
        set attack? false
        set war? false
        set local-resources 0
        set hidden? true
      ]
    ]
    create-fronts-from neighbor-states with [not member? self front-neighbors][
      set attack? false
      set war? false
      set local-resources 0
      set hidden? true
    ]

  ]

end

to check-victories
  ask fronts [
    if war? [
      let transpose (front ([who] of end2) ([who] of end1) )
      if ([local-resources] of transpose = 0) or (local-resources / [local-resources] of transpose > victory-ratio)[
        ask end1 [ ; end1 is the annexing state
          ;show [end2] of transpose
          ;pick a random province on the front and an adjacent province of the state being attacked to annex
          let transpose-front-provinces []
          ask control-link-neighbors[
            ask (provinces-on neighbors4) with [one-of control-link-neighbors = ([end1] of transpose)] [
              set transpose-front-provinces (lput self transpose-front-provinces)
            ]
          ]
          set transpose-front-provinces (provinces with [member? self transpose-front-provinces])

          ;province to get annexed
          ask one-of transpose-front-provinces[
            let annexing-state myself

            ;if the state is also on the same patch of the province that got annexed
            ifelse any? states-on patch-here [
              ;Checks if province count is greater than 1, if so each province becomes their own state (not including the captured province)
              ;if any? (states-on patch-here) with [count my-control-links > 1] [
                ;ask the provinces controlled by the capital that was annexed
                ask [control-link-neighbors] of ([end1] of transpose) [
                  ; kill control-link to old capital from annexed capital province
                  ask my-control-links [ die ]
                  ;if the province is not the annexed province, create new state and associate with province it is on
                  if (self != myself) [create-new-state self transpose]
                ]
              ;]

              ;update the annexed province
              ;i.e. change the color and label to the annexing state and kill the old state on that province
              set color [color] of one-of provinces-on [patch-here] of myself
              set label one-of [label] of provinces-on [patch-here] of myself
              ask patch-here [ set pcolor [color] of myself ]


              ; kill loser state
              ask [end1] of transpose [ die ]
              ;create a control link between the annexed province and the annexing state
              create-control-link-with myself
              ask my-control-links [ set hidden? true ]
            ]

            ;if annexed province is not capital province
            [
              ;kill the control link between the annexed province and its original state
              ask state (one-of [label] of provinces-on patch-here) [
                ask control-link who ([who] of (one-of provinces-on [patch-here] of myself))[
                  die
                ]
              ]
              ;update the annexed province
              ;i.e. change the color and label to the annexing state
              set color [color] of one-of provinces-on [patch-here] of annexing-state
              set label one-of [label] of provinces-on [patch-here] of annexing-state
              ask patch-here [ set pcolor [color] of myself ]

              ;create a control link between the annexed province and the annexing state
              create-control-link-with annexing-state
              ask my-control-links [ set hidden? true ]
              ;check if annexing the province has created "enclaves"
              ;if so then all provinces of said enclave become sovereign states
              ask [end1] of transpose [
                let loser-state self
                let num_enclave_provinces 0
                let enclave-provinces []
                ask control-link-neighbors with [(not (member? self (contiguous_provinces loser-state)))] [
                  set num_enclave_provinces num_enclave_provinces + 1
                  set enclave-provinces lput self enclave-provinces
                ]
                set enclave-provinces (provinces with [member? self enclave-provinces])

                ask enclave-provinces [
                  ask my-control-links [die]
                  create-new-state self transpose
                ]
              ]
            ]

            ;update fronts for the annexing state
            let new-neighbor-states [[one-of control-link-neighbors] of provinces-on neighbors4] of patch-here
            set new-neighbor-states (states with [member? self new-neighbor-states])
            ask new-neighbor-states [ ; ask new neighbor states

              if (self != annexing-state) and (not member? annexing-state front-neighbors)  [
                create-front-to annexing-state[
                  set attack? false
                  set war? false
                  set local-resources 0
                  set hidden? true
                ]
                ask annexing-state[
                  create-front-to myself[
                    set attack? false
                    set war? false
                    set local-resources 0
                    set hidden? true
                  ]
                ]
              ]
            ]

;            let currlabel [who] of myself
;            ;let current-label (one-of [label] of provinces-on [patch-here] of myself)
;            let neighbor-provinces []
;
;            ;find neighbor provinces (not under fielty to the same state) of all provinces in the state
;            ask myself [
;              ask control-link-neighbors [
;                ask provinces-on neighbors4 [
;                  if label != currlabel [;current-label [
;                    set neighbor-provinces lput self neighbor-provinces
;                  ]
;                ]
;              ]
;            ]
;
;            ;find neighbor provinces of the province annexed
;;            ask provinces-on neighbors4 [
;;              if label != current-label [
;;                set neighbor-provinces lput self neighbor-provinces
;;              ]
;;            ]
;;            show neighbor-provinces
;            set neighbor-provinces (provinces with [member? self neighbor-provinces])
;            let neighbor-states ([one-of control-link-neighbors] of neighbor-provinces)
;;            show neighbor-states
;            set neighbor-states (states with [member? self neighbor-states])
;
;
;
;            ask myself [
;              ask my-in-fronts [die]
;              ask my-out-fronts [die]
;
;              create-fronts-to neighbor-states [
;                set attack? false
;                set war? false
;                set local-resources 0
;                set hidden? true
;              ]
;
;              create-fronts-from neighbor-states [
;                 set attack? false
;                 set war? false
;                 set local-resources 0
;                 set hidden? true
;               ]
;            ]
          ]
        ]

      ]
    ]
  ]
end


;s is the state
to-report contiguous_provinces [s]
  let state-province one-of (provinces-on [patch-here] of s)
  let contiguous-provinces []
  let stack []
  let seen []
  ask s [
    ;DO BFS TO FIND THE CONTIGUOUS PROVINCES
    ask (provinces-on [neighbors4] of patch-here) [
      if (label = [who] of s) [
        set stack lput self stack
      ]
    ]
  ]
  while [not empty? stack][
    let current last stack
    set stack remove-item (length stack - 1) stack
    ask (provinces-on [neighbors4] of current) [
      if (label = [who] of s and (not (member? self seen)) and (not (member? self stack))) [
        set stack lput self stack
        set seen lput self seen
      ]
    ]
    set contiguous-provinces lput current contiguous-provinces
  ]
  set contiguous-provinces lput state-province contiguous-provinces
  report contiguous-provinces
end

; divide resources evenly between the fronts
to reallocate-resources
  ask states [
    let c count my-out-fronts
    ask my-out-fronts [
      set local-resources ([resources] of myself) / c
    ]
  ]
end

; each state harvests resources for each province it controls
to harvest
  ask states [
   repeat (count control-link-neighbors) [
     set resources (resources + random-normal harvest-mean harvest-std-dev)
    ]
  ]
end

to create-new-state [seed-province transpose-front]
  ask seed-province[
    ask patch-here [
      sprout-states 1 [set color black set shape "circle" set size 0.25]
    ]
    ;set the province label and color of the newly created sovereign state
    ask (provinces-on patch-here) [
      set label [who] of one-of (states-on patch-here)
      set color one-of remove red base-colors
      while [member? color ([color] of provinces-on [neighbors4] of patch-here)] [
        set color one-of remove red base-colors
      ]
      ask patch-here [
        set pcolor [color] of myself
      ]
    ]

    ask (states-on patch-here)[ ;with [who != [who] of ([end2] of transpose)] [ ; do we need this with check?

      ;create control links from the newly created state on the province to the province
      create-control-links-with (provinces-here with [label != [label] of myself])
      ask control-link-neighbors [
        set label [who] of myself
        set label-color black
      ]

      ;keep with the initial predator distribution for the newly created states
      set predator? (random-float 1 < proportion-predators)
      ask states with [predator? = true] [set color red]

      ;allocate an even percentage of the resources to each new sovereign state
      set resources ([resources] of ([end2] of transpose-front) / (count my-control-links))
      compute-fronts self
    ]
  ]
end

; creates fronts for new state
to compute-fronts [seed-state]
  ; note - use neighbors 4, von neumann
  ask seed-state [
        let neighbor-states ([one-of control-link-neighbors] of (provinces-on ([neighbors4] of one-of control-link-neighbors) ))
        set neighbor-states (states with [member? self neighbor-states]) ; turn from a list to an agentsset
        create-fronts-to neighbor-states [
          set attack? false
          set war? false
          set local-resources 0
          set hidden? true
        ]
    create-fronts-from neighbor-states [
      set attack? false
      set war? false
      set local-resources 0
      set hidden? true
    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
271
15
719
464
-1
-1
44.0
1
10
1
1
1
0
0
0
1
0
9
0
9
0
0
1
ticks
30.0

SLIDER
18
78
191
111
proportion-predators
proportion-predators
0
1
0.27
.01
1
NIL
HORIZONTAL

SLIDER
16
122
189
155
superiority-ratio
superiority-ratio
1
5
2.0
.5
1
NIL
HORIZONTAL

SLIDER
18
167
191
200
victory-ratio
victory-ratio
1
5
2.0
.5
1
NIL
HORIZONTAL

SLIDER
17
226
190
259
initial-resource-mean
initial-resource-mean
1
100
50.0
1
1
NIL
HORIZONTAL

SLIDER
17
269
196
302
initial-resource-std-dev
initial-resource-std-dev
0
20
10.0
1
1
NIL
HORIZONTAL

SLIDER
18
328
191
361
harvest-mean
harvest-mean
0
10
2.0
1
1
NIL
HORIZONTAL

SLIDER
17
369
190
402
harvest-std-dev
harvest-std-dev
0
10
5.0
1
1
NIL
HORIZONTAL

BUTTON
21
18
87
51
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
95
18
158
51
NIL
step
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
169
18
232
51
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
17
427
198
460
defensive-alliances?
defensive-alliances?
1
1
-1000

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.4
@#$#@#$#@
@#$#@#$#@
1.0
    org.nlogo.sdm.gui.AggregateDrawing 1
        org.nlogo.sdm.gui.StockFigure "attributes" "attributes" 1 "FillColor" "Color" 225 225 182 220 97 60 40
            org.nlogo.sdm.gui.WrappedStock "" "" 0
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="5000"/>
    <metric>count states</metric>
    <steppedValueSet variable="victory-ratio" first="1" step="0.2" last="2"/>
    <steppedValueSet variable="initial-resource-mean" first="0" step="50" last="100"/>
    <steppedValueSet variable="superiority-ratio" first="1" step="0.2" last="2"/>
    <steppedValueSet variable="harvest-std-dev" first="0" step="5" last="10"/>
    <steppedValueSet variable="harvest-mean" first="1" step="3" last="10"/>
    <steppedValueSet variable="proportion-predators" first="0" step="0.5" last="1"/>
    <steppedValueSet variable="initial-resource-std-dev" first="0" step="10" last="20"/>
  </experiment>
  <experiment name="experiment" repetitions="50" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000"/>
    <metric>count states</metric>
    <metric>count states with [count control-link-neighbors &gt; 1]</metric>
    <metric>count states with [count control-link-neighbors &gt; 2]</metric>
    <metric>count states with [count control-link-neighbors &gt; 5]</metric>
    <metric>count states with [count control-link-neighbors &gt; 10]</metric>
    <metric>count states with [count control-link-neighbors &gt; 20]</metric>
    <metric>count states with [count control-link-neighbors &gt; 30]</metric>
    <enumeratedValueSet variable="initial-resource-mean">
      <value value="50"/>
    </enumeratedValueSet>
    <steppedValueSet variable="superiority-ratio" first="2" step="0.25" last="3"/>
    <enumeratedValueSet variable="harvest-std-dev">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="harvest-mean">
      <value value="2"/>
    </enumeratedValueSet>
    <steppedValueSet variable="proportion-predators" first="0.05" step="0.05" last="1"/>
    <enumeratedValueSet variable="initial-resource-std-dev">
      <value value="10"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Cederman-Offensive-Orientation" repetitions="20" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000"/>
    <metric>count states</metric>
    <enumeratedValueSet variable="victory-ratio">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-resource-mean">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="superiority-ratio">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="harvest-std-dev">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="harvest-mean">
      <value value="2"/>
    </enumeratedValueSet>
    <steppedValueSet variable="proportion-predators" first="0.05" step="0.05" last="1"/>
    <enumeratedValueSet variable="initial-resource-std-dev">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="defensive-alliances?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
