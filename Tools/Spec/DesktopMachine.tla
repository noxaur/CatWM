---------------------------- MODULE DesktopMachine ----------------------------
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Requests, Windows, MaxJobs, MaxMoves, MaxInputs, None

Show == [kind |-> "show", window |-> None]
Caller == [kind |-> "caller", window |-> None]
Purposes == {Show, Caller} \cup {[kind |-> "window", window |-> w] : w \in Windows}
Works == {[kind |-> "remove", purpose |-> Caller]} \cup {[kind |-> "create", purpose |-> p] : p \in Purposes}

VARIABLES wanted, slide, held, queue, moving, waiting, nextId, nextMove, inputs, answered, started

vars == <<wanted, slide, held, queue, moving, waiting, nextId, nextMove, inputs, answered, started>>

IsShow(job) == job.work.kind = "create" /\ job.work.purpose = Show
IsWindow(job, w) == job.work.kind = "create" /\ job.work.purpose = [kind |-> "window", window |-> w]
IsRemoval(h) == h # None /\ h.job.work.kind = "remove"
Idle == slide = None /\ held = None
Tracking == slide # None /\ slide.gesture = "tracking"
QueueIds == {queue[i].id : i \in 1..Len(queue)}
Filter(s, Test(_)) == SelectSeq(s, Test)
Ids(s) == {s[i].id : i \in 1..Len(s)}
Grantable(job, m) == job.work.kind # "remove" \/ m = {}
RemoveAt(s, i) == SubSeq(s, 1, i - 1) \o SubSeq(s, i + 1, Len(s))

Release(s) == IF s # None /\ s.gesture = "tracking" THEN [s EXCEPT !.gesture = "released"] ELSE s

\* The reducer after each event body: moves held back by a removal start once it ends,
\* then an idle machine starts the wanted slide, else grants the first job that may run.
Commit(w, s, h, q, a, m, wm) ==
    LET free == ~IsRemoval(h)
        m2 == IF free THEN m \cup wm ELSE m
        wm2 == IF free THEN {} ELSE wm
        grantable == {i \in 1..Len(q) : Grantable(q[i], m2)}
        first == CHOOSE i \in grantable : \A k \in grantable : i <= k
    IN /\ moving' = m2 /\ waiting' = wm2 /\ started' = started \cup m2
       /\ IF s = None /\ h = None /\ w # None
          THEN wanted' = w /\ slide' = [target |-> w, gesture |-> "none"] /\ held' = h /\ queue' = q
               /\ answered' = a
          ELSE IF s = None /\ h = None /\ grantable # {}
               THEN /\ wanted' = w /\ slide' = s /\ held' = [job |-> q[first], current |-> TRUE]
                    /\ queue' = RemoveAt(q, first) /\ answered' = a \cup {q[first].id}
               ELSE wanted' = w /\ slide' = s /\ held' = h /\ queue' = q /\ answered' = a

Keep(w, s, h, q, a) == Commit(w, s, h, q, a, moving, waiting)

SupersedeShows(h, q, a) ==
    LET kept == Filter(q, LAMBDA j : ~IsShow(j))
        h2 == IF h # None /\ IsShow(h.job) THEN [h EXCEPT !.current = FALSE] ELSE h
    IN <<h2, kept, a \cup (Ids(q) \ Ids(kept))>>

Input == inputs < MaxInputs /\ inputs' = inputs + 1

Request(r) ==
    /\ Input
    /\ LET x == SupersedeShows(held, queue, answered) IN Keep(r, Release(slide), x[1], x[2], x[3])
    /\ UNCHANGED <<nextId, nextMove>>

BeginGesture(r) ==
    /\ Input
    /\ Idle
    /\ wanted' = r /\ slide' = [target |-> r, gesture |-> "tracking"]
    /\ UNCHANGED <<held, queue, moving, waiting, nextId, nextMove, answered, started>>

EndGesture(commit) ==
    /\ Input
    /\ Tracking
    /\ Keep(IF commit THEN wanted ELSE None, [slide EXCEPT !.gesture = "released"], held, queue, answered)
    /\ UNCHANGED <<nextId, nextMove>>

Stop ==
    /\ Input
    /\ LET x == SupersedeShows(held, queue, answered) IN Keep(None, Release(slide), x[1], x[2], x[3])
    /\ UNCHANGED <<nextId, nextMove>>

SlideFinished ==
    /\ slide # None
    /\ Keep(IF wanted = slide.target THEN None ELSE wanted, None, held, queue, answered)
    /\ UNCHANGED <<nextId, nextMove, inputs>>

Enqueue(work) ==
    /\ Input
    /\ nextId < MaxJobs
    /\ nextId' = nextId + 1
    /\ LET job == [id |-> nextId, work |-> work]
           show == work.kind = "create" /\ work.purpose = Show
           x == IF show THEN SupersedeShows(held, queue, answered) ELSE <<held, queue, answered>>
       IN Keep(IF show THEN None ELSE wanted, IF show THEN Release(slide) ELSE slide,
               x[1], Append(x[2], job), x[3])
    /\ UNCHANGED nextMove

Cancel(id) ==
    /\ Input
    /\ LET kept == Filter(queue, LAMBDA j : j.id # id)
           h == IF held # None /\ held.job.id = id THEN [held EXCEPT !.current = FALSE] ELSE held
       IN Keep(wanted, slide, h, kept, answered \cup (Ids(queue) \ Ids(kept)))
    /\ UNCHANGED <<nextId, nextMove>>

CancelWindow(w) ==
    /\ Input
    /\ LET kept == Filter(queue, LAMBDA j : ~IsWindow(j, w))
           h == IF held # None /\ IsWindow(held.job, w) THEN [held EXCEPT !.current = FALSE] ELSE held
       IN Keep(wanted, slide, h, kept, answered \cup (Ids(queue) \ Ids(kept)))
    /\ UNCHANGED <<nextId, nextMove>>

Finished(created) ==
    /\ held # None
    /\ LET w == IF held.current /\ IsShow(held.job) /\ created # None THEN created ELSE wanted
       IN Keep(w, slide, None, queue, answered)
    /\ UNCHANGED <<nextId, nextMove, inputs>>

MoveRequested ==
    /\ Input
    /\ nextMove < MaxMoves
    /\ nextMove' = nextMove + 1
    /\ IF IsRemoval(held)
       THEN Commit(wanted, slide, held, queue, answered, moving, waiting \cup {nextMove})
       ELSE Commit(wanted, slide, held, queue, answered, moving \cup {nextMove}, waiting)
    /\ UNCHANGED nextId

MoveEnded(id) ==
    /\ id \in moving
    /\ Commit(wanted, slide, held, queue, answered, moving \ {id}, waiting)
    /\ UNCHANGED <<nextId, nextMove, inputs>>

Init ==
    /\ wanted = None /\ slide = None /\ held = None /\ queue = <<>>
    /\ moving = {} /\ waiting = {} /\ nextId = 0 /\ nextMove = 0 /\ inputs = 0
    /\ answered = {} /\ started = {}

Next ==
    \/ \E r \in Requests : Request(r) \/ BeginGesture(r)
    \/ \E c \in BOOLEAN : EndGesture(c)
    \/ Stop
    \/ SlideFinished
    \/ \E work \in Works : Enqueue(work)
    \/ \E id \in 0..(MaxJobs - 1) : Cancel(id)
    \/ \E w \in Windows : CancelWindow(w)
    \/ \E created \in Requests \cup {None} : Finished(created)
    \/ MoveRequested
    \/ \E id \in 0..(MaxMoves - 1) : MoveEnded(id)

Spec ==
    /\ Init /\ [][Next]_vars
    /\ WF_vars(SlideFinished)
    /\ WF_vars(\E c \in Requests \cup {None} : Finished(c))
    /\ \A id \in 0..(MaxMoves - 1) : WF_vars(MoveEnded(id))

TypeOK ==
    /\ wanted \in Requests \cup {None}
    /\ slide = None \/ (slide.target \in Requests /\ slide.gesture \in {"none", "tracking", "released"})
    /\ held = None \/ held.current \in BOOLEAN
    /\ moving \subseteq 0..(MaxMoves - 1) /\ waiting \subseteq 0..(MaxMoves - 1)

NoSlideWhileLocked == ~(slide # None /\ held # None)
IdleMeansDone ==
    Idle => /\ wanted = None
            /\ \A i \in 1..Len(queue) : queue[i].work.kind = "remove"
            /\ (queue = <<>> \/ moving # {})
TrackingFollowsWanted == Tracking => wanted = slide.target
ShowCount ==
    Cardinality({i \in 1..Len(queue) : IsShow(queue[i])})
        + (IF held # None /\ held.current /\ IsShow(held.job) THEN 1 ELSE 0)
        + (IF wanted # None THEN 1 ELSE 0)
OneShow == ShowCount <= 1
UniqueJobs == Len(queue) = Cardinality(QueueIds) /\ (held = None \/ held.job.id \notin QueueIds)
NoAnswerTwice == QueueIds \cap answered = {}
AnsweredOnlyOnce == \A id \in answered : id < nextId
NoRemovalDuringMove == IsRemoval(held) => moving = {}
MovesWaitOnlyForRemoval == waiting # {} => IsRemoval(held)
MovesStartOnce == moving \cap waiting = {} /\ started \cap waiting = {}

EventuallyIdle == <>[](Idle /\ moving = {})
EveryJobAnswered == \A id \in 0..(MaxJobs - 1) : [](id < nextId => <>(id \in answered))
EveryMoveStarts == \A id \in 0..(MaxMoves - 1) : [](id < nextMove => <>(id \in started))
=============================================================================
