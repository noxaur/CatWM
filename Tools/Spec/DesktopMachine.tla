---------------------------- MODULE DesktopMachine ----------------------------
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Requests, Windows, MaxJobs, MaxInputs, None

Show == [kind |-> "show", window |-> None]
Caller == [kind |-> "caller", window |-> None]
Purposes == {Show, Caller} \cup {[kind |-> "window", window |-> w] : w \in Windows}
Works == {[kind |-> "remove", purpose |-> Caller]} \cup {[kind |-> "create", purpose |-> p] : p \in Purposes}

VARIABLES wanted, slide, held, queue, nextId, inputs, answered

vars == <<wanted, slide, held, queue, nextId, inputs, answered>>

IsShow(job) == job.work.kind = "create" /\ job.work.purpose = Show
IsWindow(job, w) == job.work.kind = "create" /\ job.work.purpose = [kind |-> "window", window |-> w]
Idle == slide = None /\ held = None
Tracking == slide # None /\ slide.gesture = "tracking"
QueueIds == {queue[i].id : i \in 1..Len(queue)}
Filter(s, Test(_)) == SelectSeq(s, Test)
Ids(s) == {s[i].id : i \in 1..Len(s)}

Release(s) == IF s # None /\ s.gesture = "tracking" THEN [s EXCEPT !.gesture = "released"] ELSE s

\* One step of the reducer after the event body: start a slide, else grant the next job.
Advance(w, s, h, q, a) ==
    IF s = None /\ h = None
    THEN IF w # None
         THEN <<w, [target |-> w, gesture |-> "none"], h, q, a>>
         ELSE IF q # <<>>
              THEN <<w, s, [job |-> Head(q), current |-> TRUE], Tail(q), a \cup {Head(q).id}>>
              ELSE <<w, s, h, q, a>>
    ELSE <<w, s, h, q, a>>

Commit(w, s, h, q, a) ==
    LET n == Advance(w, s, h, q, a) IN
    /\ wanted' = n[1] /\ slide' = n[2] /\ held' = n[3] /\ queue' = n[4] /\ answered' = n[5]

SupersedeShows(h, q, a) ==
    LET kept == Filter(q, LAMBDA j : ~IsShow(j))
        gone == Ids(q) \ Ids(kept)
        h2 == IF h # None /\ IsShow(h.job) THEN [h EXCEPT !.current = FALSE] ELSE h
    IN <<h2, kept, a \cup gone>>

Input == inputs < MaxInputs /\ inputs' = inputs + 1

Request(r) ==
    /\ Input
    /\ LET x == SupersedeShows(held, queue, answered)
           s == Release(slide)
       IN Commit(r, s, x[1], x[2], x[3])
    /\ UNCHANGED nextId

BeginGesture(r) ==
    /\ Input
    /\ Idle
    /\ wanted' = r /\ slide' = [target |-> r, gesture |-> "tracking"]
    /\ UNCHANGED <<held, queue, nextId, answered>>

EndGesture(commit) ==
    /\ Input
    /\ Tracking
    /\ Commit(IF commit THEN wanted ELSE None, [slide EXCEPT !.gesture = "released"], held, queue, answered)
    /\ UNCHANGED nextId

Stop ==
    /\ Input
    /\ LET x == SupersedeShows(held, queue, answered) IN Commit(None, Release(slide), x[1], x[2], x[3])
    /\ UNCHANGED nextId

SlideFinished ==
    /\ slide # None
    /\ Commit(IF wanted = slide.target THEN None ELSE wanted, None, held, queue, answered)
    /\ UNCHANGED <<nextId, inputs>>

Enqueue(work) ==
    /\ Input
    /\ nextId < MaxJobs
    /\ nextId' = nextId + 1
    /\ LET job == [id |-> nextId, work |-> work]
           show == work.kind = "create" /\ work.purpose = Show
           x == IF show THEN SupersedeShows(held, queue, answered) ELSE <<held, queue, answered>>
       IN Commit(IF show THEN None ELSE wanted, IF show THEN Release(slide) ELSE slide,
                 x[1], Append(x[2], job), x[3])

Cancel(id) ==
    /\ Input
    /\ LET kept == Filter(queue, LAMBDA j : j.id # id)
           h == IF held # None /\ held.job.id = id THEN [held EXCEPT !.current = FALSE] ELSE held
       IN Commit(wanted, slide, h, kept, answered \cup (Ids(queue) \ Ids(kept)))
    /\ UNCHANGED nextId

CancelWindow(w) ==
    /\ Input
    /\ LET kept == Filter(queue, LAMBDA j : ~IsWindow(j, w))
           h == IF held # None /\ IsWindow(held.job, w) THEN [held EXCEPT !.current = FALSE] ELSE held
       IN Commit(wanted, slide, h, kept, answered \cup (Ids(queue) \ Ids(kept)))
    /\ UNCHANGED nextId

Finished(created) ==
    /\ held # None
    /\ LET w == IF held.current /\ IsShow(held.job) /\ created # None THEN created ELSE wanted
       IN Commit(w, slide, None, queue, answered)
    /\ UNCHANGED <<nextId, inputs>>

Init ==
    /\ wanted = None /\ slide = None /\ held = None /\ queue = <<>>
    /\ nextId = 0 /\ inputs = 0 /\ answered = {}

Next ==
    \/ \E r \in Requests : Request(r) \/ BeginGesture(r)
    \/ \E c \in BOOLEAN : EndGesture(c)
    \/ Stop
    \/ SlideFinished
    \/ \E work \in Works : Enqueue(work)
    \/ \E id \in 0..(MaxJobs - 1) : Cancel(id)
    \/ \E w \in Windows : CancelWindow(w)
    \/ \E created \in Requests \cup {None} : Finished(created)

Spec == Init /\ [][Next]_vars /\ WF_vars(SlideFinished) /\ WF_vars(\E c \in Requests \cup {None} : Finished(c))

TypeOK ==
    /\ wanted \in Requests \cup {None}
    /\ slide = None \/ (slide.target \in Requests /\ slide.gesture \in {"none", "tracking", "released"})
    /\ held = None \/ held.current \in BOOLEAN

NoSlideWhileLocked == ~(slide # None /\ held # None)
IdleMeansDone == Idle => (wanted = None /\ queue = <<>>)
TrackingFollowsWanted == Tracking => wanted = slide.target
ShowCount ==
    Cardinality({i \in 1..Len(queue) : IsShow(queue[i])})
        + (IF held # None /\ held.current /\ IsShow(held.job) THEN 1 ELSE 0)
        + (IF wanted # None THEN 1 ELSE 0)
OneShow == ShowCount <= 1
UniqueJobs == Len(queue) = Cardinality(QueueIds) /\ (held = None \/ held.job.id \notin QueueIds)
NoAnswerTwice == QueueIds \cap answered = {}
AnsweredOnlyOnce == \A id \in answered : id < nextId

EventuallyIdle == <>[]Idle
EveryJobAnswered == \A id \in 0..(MaxJobs - 1) : [](id < nextId => <>(id \in answered))
=============================================================================
