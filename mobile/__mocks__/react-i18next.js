const useTranslation = () => ({
  t: (key, fallback) => fallback ?? key,
});
module.exports = { useTranslation };
