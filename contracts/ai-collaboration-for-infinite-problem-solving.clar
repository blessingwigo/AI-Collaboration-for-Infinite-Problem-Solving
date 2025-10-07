(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-insufficient-stake (err u105))
(define-constant err-invalid-status (err u106))
(define-constant err-agent-inactive (err u107))
(define-constant err-insufficient-reputation (err u108))
(define-constant err-collaboration-full (err u109))
(define-constant err-problem-locked (err u110))

(define-data-var next-problem-id uint u1)
(define-data-var next-agent-id uint u1)
(define-data-var next-collaboration-id uint u1)
(define-data-var next-solution-id uint u1)
(define-data-var platform-fee uint u30)
(define-data-var min-agent-stake uint u2000)
(define-data-var collaboration-reward-bonus uint u1000)
(define-data-var problem-generation-reward uint u500)

(define-map problems uint {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    category: (string-ascii 50),
    difficulty-level: uint,
    reward-pool: uint,
    status: (string-ascii 20),
    created-at: uint,
    collaboration-count: uint,
    solution-count: uint,
    ai-agents-involved: uint,
    complexity-score: uint
})

(define-map ai-agents uint {
    owner: principal,
    agent-name: (string-ascii 50),
    specialization: (string-ascii 100),
    reputation-score: uint,
    problems-solved: uint,
    collaborations-completed: uint,
    total-rewards-earned: uint,
    is-active: bool,
    learning-rate: uint,
    problem-generation-count: uint,
    stake-amount: uint
})

(define-map collaborations uint {
    problem-id: uint,
    participating-agents: (list 10 uint),
    collaboration-type: (string-ascii 30),
    status: (string-ascii 20),
    created-at: uint,
    consensus-threshold: uint,
    current-consensus: uint,
    reward-distribution: (list 10 uint),
    knowledge-share-count: uint,
    breakthrough-achieved: bool
})

(define-map solutions uint {
    problem-id: uint,
    collaboration-id: uint,
    submitting-agent: uint,
    solution-data: (string-ascii 400),
    innovation-score: uint,
    validation-status: (string-ascii 20),
    votes-received: uint,
    implementation-feasibility: uint,
    created-at: uint,
    ai-confidence-level: uint
})

(define-map agent-knowledge-base {agent-id: uint, domain: (string-ascii 30)} {
    expertise-level: uint,
    knowledge-items: uint,
    last-updated: uint,
    shared-count: uint
})

(define-map problem-difficulty-scaling uint {
    min-agents-required: uint,
    base-reward-multiplier: uint,
    complexity-threshold: uint,
    auto-generation-enabled: bool
})

(define-map collaboration-networks uint {
    network-type: (string-ascii 30),
    member-agents: (list 20 uint),
    network-efficiency: uint,
    total-problems-solved: uint,
    collective-iq: uint,
    formation-timestamp: uint
})

(define-public (register-ai-agent 
    (agent-name (string-ascii 50))
    (specialization (string-ascii 100))
    (initial-stake uint))
    (let ((agent-id (var-get next-agent-id)))
        (asserts! (>= initial-stake (var-get min-agent-stake)) err-insufficient-stake)
        (try! (stx-transfer? initial-stake tx-sender (as-contract tx-sender)))
        (map-set ai-agents agent-id {
            owner: tx-sender,
            agent-name: agent-name,
            specialization: specialization,
            reputation-score: u100,
            problems-solved: u0,
            collaborations-completed: u0,
            total-rewards-earned: u0,
            is-active: true,
            learning-rate: u50,
            problem-generation-count: u0,
            stake-amount: initial-stake
        })
        (var-set next-agent-id (+ agent-id u1))
        (ok agent-id)))

(define-public (create-infinite-problem
    (title (string-ascii 100))
    (description (string-ascii 500))
    (category (string-ascii 50))
    (difficulty-level uint)
    (reward-amount uint)
    (complexity-score uint))
    (let ((problem-id (var-get next-problem-id)))
        (asserts! (>= reward-amount u100) err-invalid-amount)
        (try! (stx-transfer? reward-amount tx-sender (as-contract tx-sender)))
        (map-set problems problem-id {
            creator: tx-sender,
            title: title,
            description: description,
            category: category,
            difficulty-level: difficulty-level,
            reward-pool: reward-amount,
            status: "active",
            created-at: stacks-block-height,
            collaboration-count: u0,
            solution-count: u0,
            ai-agents-involved: u0,
            complexity-score: complexity-score
        })
        (map-set problem-difficulty-scaling problem-id {
            min-agents-required: (calculate-min-agents difficulty-level),
            base-reward-multiplier: (+ u100 (* difficulty-level u20)),
            complexity-threshold: complexity-score,
            auto-generation-enabled: (> complexity-score u80)
        })
        (var-set next-problem-id (+ problem-id u1))
        (ok problem-id)))

(define-public (initiate-ai-collaboration
    (problem-id uint)
    (agent-ids (list 10 uint))
    (collaboration-type (string-ascii 30))
    (consensus-threshold uint))
    (let ((problem (unwrap! (map-get? problems problem-id) err-not-found))
          (collaboration-id (var-get next-collaboration-id)))
        (asserts! (is-eq (get status problem) "active") err-invalid-status)
        (asserts! (>= (len agent-ids) (get min-agents-required 
            (unwrap! (map-get? problem-difficulty-scaling problem-id) err-not-found))) 
            err-insufficient-stake)
        (try! (validate-agent-eligibility agent-ids))
        (map-set collaborations collaboration-id {
            problem-id: problem-id,
            participating-agents: agent-ids,
            collaboration-type: collaboration-type,
            status: "active",
            created-at: stacks-block-height,
            consensus-threshold: consensus-threshold,
            current-consensus: u0,
            reward-distribution: (generate-equal-distribution (len agent-ids)),
            knowledge-share-count: u0,
            breakthrough-achieved: false
        })
        (map-set problems problem-id 
            (merge problem {
                collaboration-count: (+ (get collaboration-count problem) u1),
                ai-agents-involved: (+ (get ai-agents-involved problem) (len agent-ids))
            }))
        (var-set next-collaboration-id (+ collaboration-id u1))
        (ok collaboration-id)))

(define-public (submit-ai-solution
    (problem-id uint)
    (collaboration-id uint)
    (agent-id uint)
    (solution-data (string-ascii 400))
    (innovation-score uint)
    (confidence-level uint))
    (let ((problem (unwrap! (map-get? problems problem-id) err-not-found))
          (collaboration (unwrap! (map-get? collaborations collaboration-id) err-not-found))
          (agent (unwrap! (map-get? ai-agents agent-id) err-not-found))
          (solution-id (var-get next-solution-id)))
        (asserts! (is-eq (get status problem) "active") err-invalid-status)
        (asserts! (is-eq (get status collaboration) "active") err-invalid-status)
        (asserts! (get is-active agent) err-agent-inactive)
        (asserts! (is-some (index-of (get participating-agents collaboration) agent-id)) err-unauthorized)
        (map-set solutions solution-id {
            problem-id: problem-id,
            collaboration-id: collaboration-id,
            submitting-agent: agent-id,
            solution-data: solution-data,
            innovation-score: innovation-score,
            validation-status: "pending",
            votes-received: u0,
            implementation-feasibility: u0,
            created-at: stacks-block-height,
            ai-confidence-level: confidence-level
        })
        (map-set problems problem-id 
            (merge problem {solution-count: (+ (get solution-count problem) u1)}))
        (var-set next-solution-id (+ solution-id u1))
        (try! (update-agent-learning agent-id innovation-score))
        (ok solution-id)))

(define-public (validate-and-consensus
    (collaboration-id uint)
    (solution-id uint)
    (validation-score uint))
    (let ((collaboration (unwrap! (map-get? collaborations collaboration-id) err-not-found))
          (solution (unwrap! (map-get? solutions solution-id) err-not-found)))
        (asserts! (is-eq (get status collaboration) "active") err-invalid-status)
        (asserts! (is-eq (get validation-status solution) "pending") err-invalid-status)
        (map-set solutions solution-id 
            (merge solution {
                validation-status: "validated",
                implementation-feasibility: validation-score,
                votes-received: (+ (get votes-received solution) u1)
            }))
        (let ((new-consensus (+ (get current-consensus collaboration) validation-score)))
            (map-set collaborations collaboration-id 
                (merge collaboration {
                    current-consensus: new-consensus,
                    breakthrough-achieved: (> validation-score u90)
                }))
            (if (>= new-consensus (get consensus-threshold collaboration))
                (finalize-collaboration collaboration-id solution-id)
                (ok true)))))

(define-public (share-knowledge
    (agent-id uint)
    (domain (string-ascii 30))
    (expertise-level uint)
    (knowledge-items uint))
    (let ((agent (unwrap! (map-get? ai-agents agent-id) err-not-found)))
        (asserts! (is-eq tx-sender (get owner agent)) err-unauthorized)
        (asserts! (get is-active agent) err-agent-inactive)
        (map-set agent-knowledge-base {agent-id: agent-id, domain: domain} {
            expertise-level: expertise-level,
            knowledge-items: knowledge-items,
            last-updated: stacks-block-height,
            shared-count: u1
        })
        (try! (update-agent-reputation agent-id u5))
        (ok true)))

(define-public (create-collaboration-network
    (network-type (string-ascii 30))
    (member-agents (list 20 uint)))
    (let ((network-id (var-get next-collaboration-id)))
        (try! (validate-network-agents member-agents))
        (map-set collaboration-networks network-id {
            network-type: network-type,
            member-agents: member-agents,
            network-efficiency: (calculate-network-efficiency (len member-agents)),
            total-problems-solved: u0,
            collective-iq: (calculate-collective-iq member-agents),
            formation-timestamp: stacks-block-height
        })
        (var-set next-collaboration-id (+ network-id u1))
        (ok network-id)))

(define-public (auto-generate-problem
    (agent-id uint)
    (base-problem-id uint)
    (variation-type (string-ascii 30))
    (complexity-increase uint))
    (let ((agent (unwrap! (map-get? ai-agents agent-id) err-not-found))
          (base-problem (unwrap! (map-get? problems base-problem-id) err-not-found)))
        (asserts! (is-eq tx-sender (get owner agent)) err-unauthorized)
        (asserts! (get auto-generation-enabled 
            (unwrap! (map-get? problem-difficulty-scaling base-problem-id) err-not-found)) 
            err-problem-locked)
        (let ((new-problem-id (var-get next-problem-id))
              (new-complexity (+ (get complexity-score base-problem) complexity-increase))
              (generation-reward (var-get problem-generation-reward)))
            (map-set problems new-problem-id {
                creator: (get owner agent),
                title: (get title base-problem),
                description: (get description base-problem),
                category: (get category base-problem),
                difficulty-level: (+ (get difficulty-level base-problem) u1),
                reward-pool: generation-reward,
                status: "active",
                created-at: stacks-block-height,
                collaboration-count: u0,
                solution-count: u0,
                ai-agents-involved: u0,
                complexity-score: new-complexity
            })
            (try! (as-contract (stx-transfer? generation-reward tx-sender (get owner agent))))
            (map-set ai-agents agent-id 
                (merge agent {
                    problem-generation-count: (+ (get problem-generation-count agent) u1),
                    total-rewards-earned: (+ (get total-rewards-earned agent) generation-reward)
                }))
            (var-set next-problem-id (+ new-problem-id u1))
            (ok new-problem-id))))

(define-public (update-platform-settings 
    (fee uint) 
    (min-stake uint) 
    (collaboration-bonus uint)
    (generation-reward uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set platform-fee fee)
        (var-set min-agent-stake min-stake)
        (var-set collaboration-reward-bonus collaboration-bonus)
        (var-set problem-generation-reward generation-reward)
        (ok true)))

(define-private (finalize-collaboration (collaboration-id uint) (winning-solution-id uint))
    (let ((collaboration (unwrap! (map-get? collaborations collaboration-id) err-not-found))
          (solution (unwrap! (map-get? solutions winning-solution-id) err-not-found))
          (problem (unwrap! (map-get? problems (get problem-id collaboration)) err-not-found)))
        (map-set collaborations collaboration-id 
            (merge collaboration {status: "completed"}))
        (map-set problems (get problem-id collaboration)
            (merge problem {status: "solved"}))
        (try! (distribute-collaboration-rewards collaboration-id))
        (try! (update-participating-agents collaboration-id))
        (ok true)))

(define-private (distribute-collaboration-rewards (collaboration-id uint))
    (let ((collaboration (unwrap! (map-get? collaborations collaboration-id) err-not-found))
          (problem (unwrap! (map-get? problems (get problem-id collaboration)) err-not-found))
          (total-reward (get reward-pool problem))
          (platform-cut (/ (* total-reward (var-get platform-fee)) u1000))
          (collaboration-reward (- total-reward platform-cut))
          (bonus-reward (if (get breakthrough-achieved collaboration) 
                           (var-get collaboration-reward-bonus) u0))
          (reward-per-agent (/ (+ collaboration-reward bonus-reward) 
                              (len (get participating-agents collaboration)))))
        (try! (as-contract (stx-transfer? platform-cut tx-sender contract-owner)))
        (try! (distribute-to-agents 
               (get participating-agents collaboration) 
               reward-per-agent))
        (ok true)))

(define-private (distribute-to-agents (agent-ids (list 10 uint)) (reward-amount uint))
    (fold distribute-single-reward agent-ids (ok reward-amount)))

(define-private (distribute-single-reward (agent-id uint) (prev-result (response uint uint)))
    (match prev-result
        reward-amount (let ((agent (unwrap! (map-get? ai-agents agent-id) err-not-found)))
                          (try! (as-contract (stx-transfer? reward-amount tx-sender (get owner agent))))
                          (map-set ai-agents agent-id 
                              (merge agent {
                                  total-rewards-earned: (+ (get total-rewards-earned agent) reward-amount)
                              }))
                          (ok reward-amount))
        error-code (err error-code)))

(define-private (update-participating-agents (collaboration-id uint))
    (let ((collaboration (unwrap! (map-get? collaborations collaboration-id) err-not-found)))
        (fold update-single-agent-stats (get participating-agents collaboration) (ok true))))

(define-private (update-single-agent-stats (agent-id uint) (prev-result (response bool uint)))
    (match prev-result
        success (let ((agent (unwrap! (map-get? ai-agents agent-id) err-not-found)))
                    (map-set ai-agents agent-id 
                        (merge agent {
                            problems-solved: (+ (get problems-solved agent) u1),
                            collaborations-completed: (+ (get collaborations-completed agent) u1),
                            reputation-score: (+ (get reputation-score agent) u10)
                        }))
                    (ok true))
        error-code (err error-code)))

(define-private (validate-agent-eligibility (agent-ids (list 10 uint)))
    (fold check-single-agent agent-ids (ok true)))

(define-private (check-single-agent (agent-id uint) (prev-result (response bool uint)))
    (match prev-result
        success (let ((agent (unwrap! (map-get? ai-agents agent-id) err-not-found)))
                    (asserts! (get is-active agent) err-agent-inactive)
                    (asserts! (>= (get reputation-score agent) u50) err-insufficient-reputation)
                    (ok true))
        error-code (err error-code)))

(define-private (validate-network-agents (agent-ids (list 20 uint)))
    (fold check-network-agent agent-ids (ok true)))

(define-private (check-network-agent (agent-id uint) (prev-result (response bool uint)))
    (match prev-result
        success (let ((agent (unwrap! (map-get? ai-agents agent-id) err-not-found)))
                    (asserts! (get is-active agent) err-agent-inactive)
                    (ok true))
        error-code (err error-code)))

(define-private (update-agent-learning (agent-id uint) (innovation-score uint))
    (let ((agent (unwrap! (map-get? ai-agents agent-id) err-not-found))
          (learning-bonus (/ innovation-score u10)))
        (map-set ai-agents agent-id 
            (merge agent {
                learning-rate: (+ (get learning-rate agent) learning-bonus),
                reputation-score: (+ (get reputation-score agent) learning-bonus)
            }))
        (ok true)))

(define-private (update-agent-reputation (agent-id uint) (reputation-increase uint))
    (let ((agent (unwrap! (map-get? ai-agents agent-id) err-not-found)))
        (map-set ai-agents agent-id 
            (merge agent {
                reputation-score: (+ (get reputation-score agent) reputation-increase)
            }))
        (ok true)))

(define-private (calculate-min-agents (difficulty-level uint))
    (+ u2 (/ difficulty-level u20)))

(define-private (calculate-network-efficiency (member-count uint))
    (if (> member-count u10) 
        (+ u80 (* (- member-count u10) u2))
        (+ u50 (* member-count u3))))

(define-private (calculate-collective-iq (agent-ids (list 20 uint)))
    (+ u100 (len agent-ids)))

(define-private (generate-equal-distribution (count uint))
    (list u100))

(define-read-only (get-problem (problem-id uint))
    (map-get? problems problem-id))

(define-read-only (get-ai-agent (agent-id uint))
    (map-get? ai-agents agent-id))

(define-read-only (get-collaboration (collaboration-id uint))
    (map-get? collaborations collaboration-id))

(define-read-only (get-solution (solution-id uint))
    (map-get? solutions solution-id))

(define-read-only (get-agent-knowledge (agent-id uint) (domain (string-ascii 30)))
    (map-get? agent-knowledge-base {agent-id: agent-id, domain: domain}))

(define-read-only (get-collaboration-network (network-id uint))
    (map-get? collaboration-networks network-id))

(define-read-only (get-platform-stats)
    {
        total-problems: (- (var-get next-problem-id) u1),
        total-agents: (- (var-get next-agent-id) u1),
        total-collaborations: (- (var-get next-collaboration-id) u1),
        total-solutions: (- (var-get next-solution-id) u1),
        platform-fee: (var-get platform-fee),
        min-agent-stake: (var-get min-agent-stake),
        collaboration-bonus: (var-get collaboration-reward-bonus),
        generation-reward: (var-get problem-generation-reward)
    })