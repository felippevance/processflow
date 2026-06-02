public with sharing class ExternalIdService {

    // Prevent recursive trigger execution
    private static Boolean triggerExecuting = false;

    public static Boolean isTriggerExecuting() { return triggerExecuting; }
    public static void setTriggerExecuting(Boolean val) { triggerExecuting = val; }

    // Generates an 8-char hex prefix — ~4 billion combinations, collision-proof in practice
    public static String generatePrefix() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8).toUpperCase();
    }

    // Slugifies a string: lowercase, spaces to dashes, strip special chars, max 40 chars
    public static String slugify(String input) {
        if (String.isBlank(input)) return 'unnamed';
        String s = input.toLowerCase()
                        .replaceAll('[^a-z0-9\\s-]', '')
                        .replaceAll('\\s+', '-')
                        .replaceAll('-{2,}', '-');
        if (s.length() > 40) s = s.substring(0, 40);
        return s.removeEnd('-');
    }

    // Process: {PREFIX}-PROC-{slug}-v{version}
    public static String forProcess(String prefix, String name, Decimal version) {
        Integer v = version == null ? 1 : Integer.valueOf(version);
        return prefix + '-PROC-' + slugify(name) + '-v' + v;
    }

    // Stage: {PREFIX}-STAGE-{slug}-{sequence}
    public static String forStage(String prefix, String name, Decimal sequence) {
        Integer seq = sequence == null ? 1 : Integer.valueOf(sequence);
        return prefix + '-STAGE-' + slugify(name) + '-' + seq;
    }

    // Step: {PREFIX}-STEP-{slug}-{stageSeq}-{stepSeq}
    public static String forStep(String prefix, String name, Decimal stageSeq, Decimal stepSeq) {
        Integer ss = stageSeq == null ? 1 : Integer.valueOf(stageSeq);
        Integer ps = stepSeq  == null ? 1 : Integer.valueOf(stepSeq);
        return prefix + '-STEP-' + slugify(name) + '-' + ss + '-' + ps;
    }
}
