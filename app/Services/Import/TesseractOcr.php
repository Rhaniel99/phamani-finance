<?php

namespace App\Services\Import;

use App\Interfaces\Services\IStatementOcr;
use GdImage;
use RuntimeException;

/**
 * OCR com Tesseract + Poppler (pdfimages/pdftoppm/pdftotext) e GD.
 *
 * 1. PDF com texto de verdade → pdftotext (instantâneo, sem OCR).
 * 2. PDF "foto" (o app do Bradesco gera um PDF com UMA imagem alta, dividida em páginas) →
 *    extrai a imagem original com pdfimages (sem reamostrar e sem a quebra de página).
 * 3. Imagens (prints) → direto.
 *
 * Cada imagem é cortada nas faixas com tinta (linhas da tabela); cada faixa é ampliada 1,5x e lida
 * com o Tesseract em modo "uma linha" (--psm 7). Faixas altas (vários parágrafos) usam --psm 6.
 * Roda $workers processos em paralelo (o i3 tem 2 núcleos).
 */
class TesseractOcr implements IStatementOcr
{
    private ?string $dir = null;

    /** @var list<GdImage> */
    private array $images = [];

    /** @var list<array{image: int|null, top: int, bottom: int, psm: int, text: string|null}> */
    private array $bands = [];

    public function __construct(
        private int $workers = 2,
        private float $scale = 1.5,
    ) {}

    public function read(array $paths, callable $progress): array
    {
        if ($this->run(['tesseract', '--version'])['code'] !== 0) {
            throw new RuntimeException('OCR indisponível no servidor (falta o tesseract-ocr / poppler-utils na imagem).');
        }

        $this->dir = sys_get_temp_dir().'/phamani-ocr-'.bin2hex(random_bytes(6));
        if (! mkdir($this->dir, 0700, true) && ! is_dir($this->dir)) {
            throw new RuntimeException('Não foi possível criar a pasta temporária do OCR.');
        }

        foreach ($paths as $path) {
            $this->load($path);
        }

        if ($this->bands === []) {
            throw new RuntimeException('Não encontrei nada para ler no arquivo.');
        }

        $pending = array_keys(array_filter($this->bands, fn (array $b) => $b['text'] === null));
        $total = count($this->bands);
        $done = $total - count($pending);
        $progress($done, $total);

        $texts = $this->ocrBands($pending, $this->scale, function () use (&$done, $total, $progress) {
            $progress(++$done, $total);
        });

        foreach ($texts as $i => $text) {
            $this->bands[$i]['text'] = $text;
        }

        return array_map(fn (array $b) => (string) $b['text'], $this->bands);
    }

    public function reread(array $bands, float $scale): array
    {
        $images = array_values(array_filter($bands, fn (int $i) => ($this->bands[$i]['image'] ?? null) !== null));
        $texts = $this->ocrBands($images, $scale);

        foreach ($bands as $i) {
            $texts[$i] ??= (string) ($this->bands[$i]['text'] ?? '');
        }

        return $texts;
    }

    public function cleanup(): void
    {
        $this->images = [];

        if ($this->dir !== null && is_dir($this->dir)) {
            foreach (glob($this->dir.'/*') ?: [] as $file) {
                @unlink($file);
            }
            @rmdir($this->dir);
        }

        $this->dir = null;
    }

    public function __destruct()
    {
        $this->cleanup();
    }

    // --- Entrada -------------------------------------------------------------------------------

    private function load(string $path): void
    {
        $mime = (string) mime_content_type($path);

        if ($mime !== 'application/pdf') {
            $this->addImage($path);

            return;
        }

        // PDF com camada de texto: não precisa de OCR.
        $text = $this->run(['pdftotext', '-layout', $path, '-'])['out'];
        if (preg_match_all('/R\$\s*-?[\d.]+,\d{2}/u', $text) >= 3) {
            foreach (preg_split('/\R/u', $text) ?: [] as $line) {
                if (trim($line) !== '') {
                    $this->bands[] = ['image' => null, 'top' => 0, 'bottom' => 0, 'psm' => 0, 'text' => $line];
                }
            }

            return;
        }

        foreach ($this->extractImages($path) as $image) {
            $this->addImage($image);
        }
    }

    /**
     * Imagens embutidas no PDF (cada objeto uma vez só). Sem imagens: renderiza as páginas a 200 dpi.
     *
     * @return list<string>
     */
    private function extractImages(string $pdf): array
    {
        $list = $this->run(['pdfimages', '-list', $pdf])['out'];

        // page num type width height color comp bpc enc interp object ID ...
        $rows = [];
        foreach (preg_split('/\R/', $list) ?: [] as $line) {
            $cols = preg_split('/\s+/', trim($line)) ?: [];
            if (count($cols) >= 12 && ctype_digit($cols[0])) {
                $rows[] = ['type' => $cols[2], 'width' => (int) $cols[3], 'height' => (int) $cols[4], 'object' => $cols[10]];
            }
        }

        $prefix = $this->dir.'/pdf'.count($this->images);
        $files = [];

        if ($rows !== []) {
            $this->run(['pdfimages', '-png', $pdf, $prefix]);
            $extracted = glob($prefix.'-*.png') ?: [];
            sort($extracted);

            $seen = [];
            foreach ($rows as $i => $row) {
                if ($row['type'] !== 'image' || isset($seen[$row['object']]) || ! isset($extracted[$i])) {
                    continue;
                }
                // Logos e ícones não interessam.
                if ($row['width'] < 400 || $row['height'] < 150) {
                    continue;
                }
                $seen[$row['object']] = true;
                $files[] = $extracted[$i];
            }
        }

        if ($files === []) {
            $this->run(['pdftoppm', '-r', '200', '-gray', '-png', $pdf, $prefix.'p']);
            $files = glob($prefix.'p-*.png') ?: [];
            sort($files);
        }

        return $files;
    }

    private function addImage(string $path): void
    {
        $raw = @imagecreatefromstring((string) file_get_contents($path));
        if (! $raw instanceof GdImage) {
            throw new RuntimeException('Arquivo de imagem inválido.');
        }

        $w = imagesx($raw);
        $h = imagesy($raw);

        // Achata transparência num fundo branco e passa para tons de cinza.
        $image = imagecreatetruecolor($w, $h);
        imagefill($image, 0, 0, (int) imagecolorallocate($image, 255, 255, 255));
        imagecopy($image, $raw, 0, 0, 0, 0, $w, $h);
        imagefilter($image, IMG_FILTER_GRAYSCALE);

        $profile = $this->rowProfile($image);

        // Tema escuro (print do app à noite): inverte.
        if (array_sum($profile) / max(1, count($profile)) < 128) {
            imagefilter($image, IMG_FILTER_NEGATE);
            $profile = array_map(fn (int $v) => 255 - $v, $profile);
        }

        $index = count($this->images);
        $this->images[] = $image;

        foreach ($this->findBands($profile, $w) as [$top, $bottom, $psm]) {
            $this->bands[] = ['image' => $index, 'top' => $top, 'bottom' => $bottom, 'psm' => $psm, 'text' => null];
        }
    }

    /**
     * Brilho médio de cada linha de pixels (0 = preto, 255 = branco).
     *
     * @return list<int>
     */
    private function rowProfile(GdImage $image): array
    {
        $w = imagesx($image);
        $h = imagesy($image);
        $step = max(1, intdiv($w, 600));

        $profile = [];
        for ($y = 0; $y < $h; $y++) {
            $sum = 0;
            $n = 0;
            for ($x = 0; $x < $w; $x += $step) {
                $sum += imagecolorat($image, $x, $y) & 0xFF;
                $n++;
            }
            $profile[] = intdiv($sum, max(1, $n));
        }

        return $profile;
    }

    /**
     * Faixas com tinta: linhas de texto. Traços finos (divisórias da tabela) são ignorados
     * e faixas muito próximas (texto em duas linhas) são unidas.
     *
     * @param  list<int>  $profile
     * @return list<array{int, int, int}> [topo, base, psm]
     */
    private function findBands(array $profile, int $width): array
    {
        $h = count($profile);
        $minHeight = max(5, intdiv($width, 300));

        $runs = [];
        for ($y = 0; $y < $h; $y++) {
            if ($profile[$y] >= 250) {
                continue;
            }
            $start = $y;
            while ($y < $h && $profile[$y] < 250) {
                $y++;
            }
            if ($y - $start >= $minHeight) {
                $runs[] = [$start, $y];
            }
        }

        if ($runs === []) {
            return [];
        }

        $heights = array_map(fn (array $r) => $r[1] - $r[0], $runs);
        sort($heights);
        $median = $heights[intdiv(count($heights), 2)];

        $merged = [array_shift($runs)];
        foreach ($runs as $run) {
            $last = &$merged[count($merged) - 1];
            if ($run[0] - $last[1] < max(3, (int) round($median * 0.35))) {
                $last[1] = $run[1];
            } else {
                $merged[] = $run;
            }
            unset($last);
        }

        $pad = max(4, (int) round($median * 0.35));

        return array_map(fn (array $r) => [
            max(0, $r[0] - $pad),
            min($h, $r[1] + $pad),
            ($r[1] - $r[0]) > $median * 2.5 ? 6 : 7,
        ], $merged);
    }

    // --- OCR -----------------------------------------------------------------------------------

    /**
     * @param  list<int>  $indexes
     * @return array<int, string>
     */
    private function ocrBands(array $indexes, float $scale, ?callable $onDone = null): array
    {
        $results = [];
        $queue = $indexes;
        /** @var array<int, array{proc: resource, pipes: array<int, resource>, out: string}> $running */
        $running = [];

        while ($queue !== [] || $running !== []) {
            while ($queue !== [] && count($running) < max(1, $this->workers)) {
                $i = array_shift($queue);
                $file = $this->cropBand($i, $scale);
                $running[$i] = $this->start(['tesseract', $file, 'stdout', '--psm', (string) $this->bands[$i]['psm']]);
            }

            foreach ($running as $i => &$job) {
                $job['out'] .= (string) stream_get_contents($job['pipes'][1]);
                stream_get_contents($job['pipes'][2]);
                $status = proc_get_status($job['proc']);
                if ($status['running']) {
                    continue;
                }
                $job['out'] .= (string) stream_get_contents($job['pipes'][1]);
                fclose($job['pipes'][1]);
                fclose($job['pipes'][2]);
                proc_close($job['proc']);

                $results[$i] = trim(preg_replace('/\R+/u', "\n", $job['out']) ?? '');
                unset($running[$i]);
                if ($onDone !== null) {
                    $onDone();
                }
            }
            unset($job);

            if ($running !== []) {
                usleep(20000);
            }
        }

        return $results;
    }

    private function cropBand(int $i, float $scale): string
    {
        $band = $this->bands[$i];
        $source = $this->images[(int) $band['image']];
        $w = imagesx($source);
        $h = $band['bottom'] - $band['top'];

        $dw = (int) round($w * $scale);
        $dh = (int) round($h * $scale);
        $crop = imagecreatetruecolor($dw, $dh);
        imagecopyresampled($crop, $source, 0, 0, 0, $band['top'], $dw, $dh, $w, $h);

        $file = sprintf('%s/b%d-%s.png', $this->dir, $i, str_replace('.', '_', (string) $scale));
        imagepng($crop, $file, 1);

        return $file;
    }

    /**
     * @param  list<string>  $command
     * @return array{proc: resource, pipes: array<int, resource>, out: string}
     */
    private function start(array $command): array
    {
        $proc = proc_open($command, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, null, [
            'OMP_THREAD_LIMIT' => '1',
            'PATH' => getenv('PATH') ?: '/usr/local/bin:/usr/bin:/bin',
        ]);

        if (! is_resource($proc)) {
            throw new RuntimeException('Não foi possível executar o Tesseract.');
        }

        stream_set_blocking($pipes[1], false);
        stream_set_blocking($pipes[2], false);

        return ['proc' => $proc, 'pipes' => $pipes, 'out' => ''];
    }

    /**
     * @param  list<string>  $command
     * @return array{code: int, out: string}
     */
    private function run(array $command): array
    {
        $proc = proc_open($command, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
        if (! is_resource($proc)) {
            throw new RuntimeException("Não foi possível executar {$command[0]}.");
        }

        $out = (string) stream_get_contents($pipes[1]);
        stream_get_contents($pipes[2]);
        fclose($pipes[1]);
        fclose($pipes[2]);

        return ['code' => proc_close($proc), 'out' => $out];
    }
}
