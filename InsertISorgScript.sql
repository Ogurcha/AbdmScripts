SET session_replication_role = replica;

INSERT INTO public.i_sorg (c_isso, n, c_typ_org, c_org, god, god_end, prim, cid) SELECT i.c_isso, COALESCE((SELECT MAX(s.n) FROM public.i_sorg s WHERE s.c_isso = i.c_isso), 0) + 1,    6,    770004,    TIMESTAMP '2025-04-14 00:00:00',    TIMESTAMP '2026-12-18 23:59:59',    'ДИС-2025/1', 223 FROM public.i_isso i where i.c_isso = 2400007; 