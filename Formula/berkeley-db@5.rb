# based on https://github.com/givanse/homebrew-core/blob/berkeley-db5/Formula/berkeley-db@5.rb
class BerkeleyDbAT5 < Formula
  desc "High performance key/value database"
  homepage "https://www.oracle.com/database/technologies/related/berkeleydb.html"
  url "http://download.oracle.com/berkeley-db/db-5.1.29.tar.gz"
  sha256 "a943cb4920e62df71de1069ddca486d408f6d7a09ddbbb5637afe7a229389182"
  license "AGPL-3.0-only"

  livecheck do
    url "https://www.oracle.com/database/technologies/related/berkeleydb-downloads.html"
    regex(%r{href=.*?/berkeley-db/db[._-]v?(\d+(?:\.\d+)+)\.t}i)
  end

  depends_on "openssl@1.1"

  patch :DATA

  def install
    # BerkeleyDB dislikes parallel builds
    ENV.deparallelize

    args = %W[
      --disable-debug
      --prefix=#{prefix}
      --mandir=#{man}
      --disable-static
      --enable-cxx
    ]

    # BerkeleyDB requires you to build everything from the build_unix subdirectory
    cd "build_unix" do
      system "../dist/configure", *args
      system "make", "install"
    end
  end

  test do
    (testpath/"test.cpp").write <<~EOS
      #include <assert.h>
      #include <string.h>
      #include <db_cxx.h>
      int main() {
        Db db(NULL, 0);
        assert(db.open(NULL, "test.db", NULL, DB_BTREE, DB_CREATE, 0) == 0);

        const char *project = "Homebrew";
        const char *stored_description = "The missing package manager for macOS";
        Dbt key(const_cast<char *>(project), strlen(project) + 1);
        Dbt stored_data(const_cast<char *>(stored_description), strlen(stored_description) + 1);
        assert(db.put(NULL, &key, &stored_data, DB_NOOVERWRITE) == 0);

        Dbt returned_data;
        assert(db.get(NULL, &key, &returned_data, 0) == 0);
        assert(strcmp(stored_description, (const char *)(returned_data.get_data())) == 0);

        assert(db.close(0) == 0);
      }
    EOS
    flags = %W[
      -I#{include}
      -L#{lib}
      -ldb_cxx
    ]
    system ENV.cxx, "test.cpp", "-o", "test", *flags
    system "./test"
    assert_predicate testpath/"test.db", :exist?
  end
end

__END__
--- a/src/dbinc/atomic.h
+++ b/src/dbinc/atomic.h
@@ -70,7 +70,7 @@ typedef struct {
  * These have no memory barriers; the caller must include them when necessary.
  */
 #define	atomic_read(p)		((p)->value)
-#define	atomic_init(p, val)	((p)->value = (val))
+#define	atomic_init_db(p, val)	((p)->value = (val))

 #ifdef HAVE_ATOMIC_SUPPORT

@@ -144,7 +144,7 @@ typedef LONG volatile *interlocked_val;
 #define	atomic_inc(env, p)	__atomic_inc(p)
 #define	atomic_dec(env, p)	__atomic_dec(p)
 #define	atomic_compare_exchange(env, p, o, n)	\
-	__atomic_compare_exchange((p), (o), (n))
+	__atomic_compare_exchange_db((p), (o), (n))
 static inline int __atomic_inc(db_atomic_t *p)
 {
	int	temp;
@@ -176,7 +176,7 @@ static inline int __atomic_dec(db_atomic_t *p)
  * http://gcc.gnu.org/onlinedocs/gcc-4.1.0/gcc/Atomic-Builtins.html
  * which configure could be changed to use.
  */
-static inline int __atomic_compare_exchange(
+static inline int __atomic_compare_exchange_db(
	db_atomic_t *p, atomic_value_t oldval, atomic_value_t newval)
 {
	atomic_value_t was;
@@ -206,7 +206,7 @@ static inline int __atomic_compare_exchange(
 #define	atomic_dec(env, p)	(--(p)->value)
 #define	atomic_compare_exchange(env, p, oldval, newval)		\
	(DB_ASSERT(env, atomic_read(p) == (oldval)),		\
-	atomic_init(p, (newval)), 1)
+	atomic_init_db(p, (newval)), 1)
 #else
 #define atomic_inc(env, p)	__atomic_inc(env, p)
 #define atomic_dec(env, p)	__atomic_dec(env, p)

--- a/src/mp/mp_fget.c
+++ b/src/mp/mp_fget.c
@@ -649,7 +649,7 @@ alloc:		/* Allocate a new buffer header and data space. */

		/* Initialize enough so we can call __memp_bhfree. */
		alloc_bhp->flags = 0;
-		atomic_init(&alloc_bhp->ref, 1);
+		atomic_init_db(&alloc_bhp->ref, 1);
 #ifdef DIAGNOSTIC
		if ((uintptr_t)alloc_bhp->buf & (sizeof(size_t) - 1)) {
			__db_errx(env, DB_STR("3025",
@@ -955,7 +955,7 @@ alloc:		/* Allocate a new buffer header and data space. */
			MVCC_MPROTECT(bhp->buf, mfp->pagesize,
			    PROT_READ);

-		atomic_init(&alloc_bhp->ref, 1);
+		atomic_init_db(&alloc_bhp->ref, 1);
		MUTEX_LOCK(env, alloc_bhp->mtx_buf);
		alloc_bhp->priority = bhp->priority;
		alloc_bhp->pgno = bhp->pgno;

--- a/src/mp/mp_mvcc.c	2011-10-25 14:39:35.000000000 -0600
+++ b/src/mp/mp_mvcc.c	2018-06-01 20:02:45.000000000 -0600
@@ -276,7 +276,7 @@
 #else
 	memcpy(frozen_bhp, bhp, SSZA(BH, buf));
 #endif
-	atomic_init(&frozen_bhp->ref, 0);
+	atomic_init_db(&frozen_bhp->ref, 0);
 	if (mutex != MUTEX_INVALID)
 		frozen_bhp->mtx_buf = mutex;
 	else if ((ret = __mutex_alloc(env, MTX_MPOOL_BH,
@@ -428,7 +428,7 @@
 #endif
 		alloc_bhp->mtx_buf = mutex;
 		MUTEX_LOCK(env, alloc_bhp->mtx_buf);
-		atomic_init(&alloc_bhp->ref, 1);
+		atomic_init_db(&alloc_bhp->ref, 1);
 		F_CLR(alloc_bhp, BH_FROZEN);
 	}
 
--- a/src/mp/mp_region.c
+++ b/src/mp/mp_region.c
@@ -245,7 +245,7 @@ __memp_init(env, dbmp, reginfo_off, htab_buckets, max_nreg)
			     MTX_MPOOL_FILE_BUCKET, 0, &htab[i].mtx_hash)) != 0)
				return (ret);
			SH_TAILQ_INIT(&htab[i].hash_bucket);
-			atomic_init(&htab[i].hash_page_dirty, 0);
+			atomic_init_db(&htab[i].hash_page_dirty, 0);
		}

		/*
@@ -302,7 +302,7 @@ no_prealloc:
		} else
			hp->mtx_hash = mtx_base + (i % dbenv->mp_mtxcount);
		SH_TAILQ_INIT(&hp->hash_bucket);
-		atomic_init(&hp->hash_page_dirty, 0);
+		atomic_init_db(&hp->hash_page_dirty, 0);
 #ifdef HAVE_STATISTICS
		hp->hash_io_wait = 0;
		hp->hash_frozen = hp->hash_thawed = hp->hash_frozen_freed = 0;

--- a/src/mutex/mut_method.c
+++ b/src/mutex/mut_method.c
@@ -474,7 +474,7 @@ atomic_compare_exchange(env, v, oldval, newval)
	MUTEX_LOCK(env, mtx);
	ret = atomic_read(v) == oldval;
	if (ret)
-		atomic_init(v, newval);
+		atomic_init_db(v, newval);
	MUTEX_UNLOCK(env, mtx);

	return (ret);

--- a/src/mutex/mut_tas.c
+++ b/src/mutex/mut_tas.c
@@ -47,7 +47,7 @@ __db_tas_mutex_init(env, mutex, flags)

 #ifdef HAVE_SHARED_LATCHES
	if (F_ISSET(mutexp, DB_MUTEX_SHARED))
-		atomic_init(&mutexp->sharecount, 0);
+		atomic_init_db(&mutexp->sharecount, 0);
	else
 #endif
	if (MUTEX_INIT(&mutexp->tas)) {
@@ -536,7 +536,7 @@ __db_tas_mutex_unlock(env, mutex)
			F_CLR(mutexp, DB_MUTEX_LOCKED);
			/* Flush flag update before zeroing count */
			MEMBAR_EXIT();
-			atomic_init(&mutexp->sharecount, 0);
+			atomic_init_db(&mutexp->sharecount, 0);
		} else {
			DB_ASSERT(env, sharecount > 0);
			MEMBAR_EXIT();
