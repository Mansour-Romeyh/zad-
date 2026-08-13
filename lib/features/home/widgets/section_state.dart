/// Lifecycle of an independently-loaded home section (categories, banners,
/// best items): each fetches on its own so one section's failure never
/// blocks the others (Task 3 brief).
enum SectionStatus { loading, error, data }

/// Holds the current [status] of a section fetch plus whichever of [data]
/// (on success) or [error] (on failure) applies.
class SectionState<T> {
  const SectionState.loading()
    : status = SectionStatus.loading,
      data = null,
      error = null;

  const SectionState.data(T value)
    : status = SectionStatus.data,
      data = value,
      error = null;

  const SectionState.error(Object err)
    : status = SectionStatus.error,
      data = null,
      error = err;

  final SectionStatus status;
  final T? data;
  final Object? error;
}
