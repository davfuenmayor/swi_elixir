#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <erl_nif.h>
#include <SWI-Prolog.h>
#include <pthread.h>
#include <string.h>
#include <dlfcn.h>
#include <stdio.h>
#include <errno.h>

/* Admission bounds live engines, GC reapers, and failed reclamations together.
   Slots outlive resources, so even a failed reaper never loses its handle. */
#define CAPACITY 64
enum slot_state { SLOT_FREE, SLOT_LIVE, SLOT_REAPING, SLOT_QUARANTINED };
typedef struct {
  PL_engine_t engine;
  enum slot_state state;
} engine_slot;
typedef struct {
  engine_slot *slot;
  ErlNifMutex *lock;
} session;

static engine_slot slots[CAPACITY];
static pthread_mutex_t slots_lock = PTHREAD_MUTEX_INITIALIZER;
static ErlNifResourceType *session_type;
static pthread_mutex_t init_lock = PTHREAD_MUTEX_INITIALIZER;

/* Fault injection exists only in separately compiled test libraries. */
static int failpoint(const char *name) {
#ifdef SWI_NIF_TESTING
  char point[64];
  size_t len = sizeof(point);
  return enif_getenv("SWI_NIF_FAIL", point, &len) == 0 && strcmp(point, name) == 0;
#else
  (void)name;
  return 0;
#endif
}
static ERL_NIF_TERM atom(ErlNifEnv *env, const char *name) {
  return enif_make_atom(env, name);
}
static ERL_NIF_TERM error(ErlNifEnv *env, const char *reason) {
  return enif_make_tuple2(env, atom(env, "error"), atom(env, reason));
}
static int binary(ErlNifEnv *env, const char *bytes, size_t len, ERL_NIF_TERM *out) {
  if (failpoint("binary")) return 0;
  unsigned char *data = enif_make_new_binary(env, len, out);
  if (!data && len) return 0;
  if (len) memcpy(data, bytes, len);
  return 1;
}
static char *exception_message(qid_t query, size_t *length) {
  char *message = NULL;
  term_t ex = PL_exception(query);
  if (ex && !PL_get_nchars(ex, length, &message, CVT_WRITEQ | REP_UTF8 | BUF_MALLOC))
    return NULL;
  return message;
}
static ERL_NIF_TERM prolog_message(ErlNifEnv *env, const char *message,
                                 size_t length, const char *fallback) {
  if (!message) return error(env, fallback);
  ERL_NIF_TERM text;
  if (!binary(env, message, length, &text)) return error(env, "out_of_memory");
  return enif_make_tuple2(env, atom(env, "error"),
                          enif_make_tuple2(env, atom(env, "prolog"), text));
}
static ERL_NIF_TERM prolog_error(ErlNifEnv *env, qid_t query, const char *fallback) {
  size_t length = 0;
  char *message = exception_message(query, &length);
  ERL_NIF_TERM result = prolog_message(env, message, length, fallback);
  if (message) PL_free(message);
  return result;
}
static int restore_engine(PL_engine_t previous) {
  return failpoint("restore") ? PL_ENGINE_INUSE : PL_set_engine(previous, NULL);
}
static engine_slot *reserve(void) {
  engine_slot *slot = NULL;
  pthread_mutex_lock(&slots_lock);
  for (int i = 0; i < CAPACITY; i++) {
    if (slots[i].state == SLOT_FREE) {
      slot = &slots[i];
      slot->state = SLOT_LIVE;
      break;
    }
  }
  pthread_mutex_unlock(&slots_lock);
  return slot;
}
static void release_slot(engine_slot *slot) {
  pthread_mutex_lock(&slots_lock);
  memset(slot, 0, sizeof(*slot));
  pthread_mutex_unlock(&slots_lock);
}
/* On destruction failure the slot retains ownership; callers may retry.
   Cleanup exceptions do not prevent destruction, but still reach the caller. */
static const char *cleanup_engine(engine_slot *slot, char **message, size_t *length) {
  PL_engine_t previous;
  if (PL_set_engine(slot->engine, &previous) != PL_ENGINE_SET) return "engine_busy";
  const char *reason = NULL;
  fid_t frame = PL_open_foreign_frame();
  if (!frame) {
    reason = "out_of_memory";
  } else {
    int discard = 1;
    qid_t q = failpoint("query") ? 0 : PL_open_query(NULL, PL_Q_NODEBUG | PL_Q_CATCH_EXCEPTION,
                            PL_predicate("close_cursor", 0, "swi_bridge"), 0);
    if (!q) {
      reason = "query_failed";
      *message = exception_message(0, length);
    } else {
      if (!PL_next_solution(q)) {
        reason = "cleanup_failed";
        *message = exception_message(q, length);
      }
      int cut = PL_cut_query(q);
      discard = cut != PL_S_NOT_INNER;
      if (cut != TRUE && !reason) {
        reason = "cut_failed";
        *message = exception_message(0, length);
      }
    }
    if (discard) PL_discard_foreign_frame(frame);
  }
  if (restore_engine(previous) != PL_ENGINE_SET) return "engine_restore_failed";
  if (failpoint("destroy") || !PL_destroy_engine(slot->engine)) return "engine_destroy_failed";
  slot->engine = NULL;
  return reason;
}
static void *reap(void *ptr) {
  engine_slot *slot = ptr;
  char *message = NULL;
  size_t length = 0;
  const char *reason = cleanup_engine(slot, &message, &length);
  if (reason) {
    fprintf(stderr, "swi_elixir: native GC cleanup failed (%s): %.*s\n",
            reason, (int)length, message ? message : "");
  }
  if (message) PL_free(message);
  if (!slot->engine) {
    release_slot(slot);
  } else {
    pthread_mutex_lock(&slots_lock);
    slot->state = SLOT_QUARANTINED;
    pthread_mutex_unlock(&slots_lock);
  }
  return NULL;
}
static void destroy(ErlNifEnv *env, void *obj) {
  (void)env;
  session *s = obj;
  if (s->lock) enif_mutex_destroy(s->lock);
  engine_slot *slot = s->slot;
  if (!slot) return;
  if (!slot->engine) {
    release_slot(slot);
    return;
  }
  pthread_t thread;
  pthread_mutex_lock(&slots_lock);
  slot->state = SLOT_REAPING;
  pthread_mutex_unlock(&slots_lock);
  int rc = failpoint("reaper") ? EAGAIN : pthread_create(&thread, NULL, reap, slot);
  if (rc == 0) {
    rc = pthread_detach(thread);
    if (rc) fprintf(stderr, "swi_elixir: reaper detach failed: %s\n", strerror(rc));
  } else {
    pthread_mutex_lock(&slots_lock);
    slot->state = SLOT_QUARANTINED;
    pthread_mutex_unlock(&slots_lock);
    fprintf(stderr, "swi_elixir: native engine quarantined; reaper failed: %s\n", strerror(rc));
  }
}
static int initialize(void) {
  pthread_mutex_lock(&init_lock);
  int ok = 1;
  if (!PL_is_initialised(NULL, NULL)) {
    /* SWI retains argv for the lifetime of the runtime. */
    static char *argv[] = {"swi_elixir", "-q", "--nosignals", "--no-packs", "-f", "none", NULL};
    ok = PL_initialise(6, argv);
    if (ok) ok = PL_set_engine(NULL, NULL) == PL_ENGINE_SET;
  }
  pthread_mutex_unlock(&init_lock);
  return ok;
}
/* Loading and RPC share one checked FLI lifecycle. Only RPC has an output. */
static ERL_NIF_TERM invoke(ErlNifEnv *env, PL_engine_t engine,
                           const ErlNifBinary *input, int rpc) {
  PL_engine_t previous;
  if (PL_set_engine(engine, &previous) != PL_ENGINE_SET) return error(env, "engine_busy");
  ERL_NIF_TERM result = error(env, "out_of_memory");
  fid_t frame = PL_open_foreign_frame();
  if (frame) {
    int discard = 1;
    term_t args = failpoint("terms") ? 0 : PL_new_term_refs(rpc ? 2 : 1);
    if (args && PL_put_chars(args, PL_ATOM | REP_UTF8, input->size, (const char *)input->data)) {
      qid_t q = failpoint("query") ? 0 : PL_open_query(NULL, PL_Q_NODEBUG | PL_Q_CATCH_EXCEPTION,
                   PL_predicate(rpc ? "rpc" : "ensure_loaded", rpc ? 2 : 1,
                                rpc ? "swi_bridge" : "user"), args);
      if (q) {
        if (!PL_next_solution(q)) result = prolog_error(env, q, rpc ? "bridge_failed" : "bridge_load_failed");
        else if (!rpc) result = atom(env, "ok");
        else {
          char *bytes = NULL;
          size_t length = 0;
          ERL_NIF_TERM text;
          if (!PL_get_nchars(args+1, &length, &bytes, CVT_ATOM | REP_UTF8 | BUF_MALLOC))
            result = prolog_error(env, 0, "invalid_reply");
          else if (!binary(env, bytes, length, &text)) result = error(env, "out_of_memory");
          else result = enif_make_tuple2(env, atom(env, "ok"), text);
          if (bytes) PL_free(bytes);
        }
        int cut = PL_cut_query(q);
        discard = cut != PL_S_NOT_INNER;
        if (cut != TRUE) result = prolog_error(env, 0, "cut_failed");
      } else result = prolog_error(env, 0, "query_failed");
    } else result = prolog_error(env, 0, "out_of_memory");
    if (discard) PL_discard_foreign_frame(frame);
  }
  if (restore_engine(previous) != PL_ENGINE_SET) result = error(env, "engine_restore_failed");
  return result;
}
static ERL_NIF_TERM open_session(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  ErlNifBinary path;
  if (!enif_inspect_binary(env, argv[0], &path)) return enif_make_badarg(env);
  if (!initialize()) return error(env, "initialization_failed");
  session *s = failpoint("resource") ? NULL : enif_alloc_resource(session_type, sizeof(*s));
  if (!s) return error(env, "out_of_memory");
  memset(s, 0, sizeof(*s));
  s->slot = reserve();
  if (!s->slot) {
    enif_release_resource(s);
    return error(env, "native_capacity");
  }
  s->lock = enif_mutex_create("swi_engine");
  if (s->lock && !failpoint("engine")) s->slot->engine = PL_create_engine(NULL);
  if (!s->lock || !s->slot->engine) {
    enif_release_resource(s);
    return error(env, "engine_failed");
  }
  ERL_NIF_TERM result = invoke(env, s->slot->engine, &path, 0);
  if (enif_is_identical(result, atom(env, "ok")))
    result = enif_make_tuple2(env, atom(env, "ok"), enif_make_resource(env, s));
  enif_release_resource(s);
  return result;
}
static ERL_NIF_TERM request(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  session *s;
  ErlNifBinary input;
  if (!enif_get_resource(env, argv[0], session_type, (void **)&s) ||
      !enif_inspect_binary(env, argv[1], &input)) return enif_make_badarg(env);
  if (enif_mutex_trylock(s->lock) != 0) return error(env, "engine_busy");
  if (!s->slot) {
    enif_mutex_unlock(s->lock);
    return error(env, "closed");
  }
  ERL_NIF_TERM result = invoke(env, s->slot->engine, &input, 1);
  enif_mutex_unlock(s->lock);
  return result;
}
static ERL_NIF_TERM close_session(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  session *s;
  if (!enif_get_resource(env, argv[0], session_type, (void **)&s)) return enif_make_badarg(env);
  if (enif_mutex_trylock(s->lock) != 0) return error(env, "engine_busy");
  ERL_NIF_TERM result = atom(env, "ok");
  if (s->slot) {
    char *message = NULL;
    size_t length = 0;
    const char *reason = cleanup_engine(s->slot, &message, &length);
    if (reason) result = s->slot->engine ? error(env, reason)
                                        : prolog_message(env, message, length, reason);
    if (message) PL_free(message);
    if (!s->slot->engine) {
      release_slot(s->slot);
      s->slot = NULL;
    }
  }
  enif_mutex_unlock(s->lock);
  return result;
}
static ERL_NIF_TERM stats(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc; (void)argv;
  unsigned int engines = 0, reapers = 0, quarantined = 0;
  pthread_mutex_lock(&slots_lock);
  for (int i = 0; i < CAPACITY; i++) {
    engines += slots[i].state != SLOT_FREE;
    reapers += slots[i].state == SLOT_REAPING;
    quarantined += slots[i].state == SLOT_QUARANTINED;
  }
  pthread_mutex_unlock(&slots_lock);
  ERL_NIF_TERM keys[] = {atom(env,"capacity"), atom(env,"engines"), atom(env,"reapers"), atom(env,"quarantined")};
  ERL_NIF_TERM values[] = {enif_make_uint(env,CAPACITY), enif_make_uint(env,engines), enif_make_uint(env,reapers), enif_make_uint(env,quarantined)};
  ERL_NIF_TERM result;
  return enif_make_map_from_arrays(env, keys, values, 4, &result) ? result : error(env,"out_of_memory");
}
static int load(ErlNifEnv *env, void **priv, ERL_NIF_TERM info) {
  (void)priv; (void)info;
  Dl_info self;
  if (!dladdr((void *)destroy, &self) ||
      !dlopen(self.dli_fname, RTLD_NOW | RTLD_NODELETE)) return -1;
  if (!dlopen("libswipl.so", RTLD_NOW | RTLD_GLOBAL)) return -1;
  session_type = enif_open_resource_type(env, NULL, "swi_session", destroy,
                                        ERL_NIF_RT_CREATE, NULL);
  return session_type ? 0 : -1;
}
static ErlNifFunc functions[] = {
  {"open", 1, open_session, ERL_NIF_DIRTY_JOB_CPU_BOUND},
  {"request", 2, request, ERL_NIF_DIRTY_JOB_CPU_BOUND},
  {"close", 1, close_session, ERL_NIF_DIRTY_JOB_CPU_BOUND},
  {"stats", 0, stats, 0}
};
ERL_NIF_INIT(Elixir.SWI.Native, functions, load, NULL, NULL, NULL)
