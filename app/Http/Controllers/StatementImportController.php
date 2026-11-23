<?php

namespace App\Http\Controllers;

use App\DTOs\Import\AcceptImportData;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\IStatementImportService;
use App\Models\Account;
use App\Models\StatementImport;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Importar o extrato do cartão (PDF ou prints do app do Bradesco):
 * upload → OCR com progresso → revisão (aceitar/recusar, renomear, categorizar) → lançar.
 */
class StatementImportController extends Controller
{
    public function __construct(
        protected IStatementImportService $imports,
        protected ICategoryService $categories,
    ) {}

    public function store(Request $request, Account $account): RedirectResponse
    {
        $userId = (string) $request->user()?->getAuthIdentifier();
        abort_unless($account->user_id === $userId && $account->isCreditCard(), 404);

        if (! $account->isConfiguredCard()) {
            return back()->withErrors(['files' => 'Configure o fechamento e o vencimento do cartão antes de importar.']);
        }

        $request->validate([
            'files' => ['required', 'array', 'min:1', 'max:10'],
            // 100 MB: o PDF do app do Bradesco é só uma imagem grande (uns 60 MB).
            'files.*' => ['file', 'mimes:pdf,png,jpg,jpeg,webp', 'max:102400'],
        ], [
            'files.required' => 'Escolha o PDF do extrato ou os prints.',
            'files.*.mimes' => 'Envie um PDF ou imagens (PNG, JPG, WEBP).',
            'files.*.max' => 'Cada arquivo pode ter no máximo 100 MB.',
        ]);

        /** @var list<\Illuminate\Http\UploadedFile> $files */
        $files = array_values((array) $request->file('files'));

        $import = $this->imports->start($userId, $account, $files);

        return redirect()->route('imports.show', $import);
    }

    public function show(Request $request, StatementImport $import): Response
    {
        $userId = $this->ensureOwner($request, $import);
        $card = $import->account;

        return Inertia::render('cards/import', [
            'card' => $card->only(['id', 'name', 'closing_day', 'due_day']),
            'import' => fn () => [
                'id' => $import->id,
                'status' => $import->status,
                'progress' => $import->progress,
                'stage' => $import->stage,
                'error' => $import->error,
                'statement_date' => $import->statement_date?->toDateString(),
                'created_count' => $import->created_count,
            ],
            'review' => fn () => $import->status === 'ready'
                ? $this->imports->review($import, $request->string('ref')->toString() ?: null)
                : null,
            'categories' => fn () => $this->categories->listForUser($userId),
        ]);
    }

    public function accept(Request $request, StatementImport $import, AcceptImportData $data): RedirectResponse
    {
        $this->ensureOwner($request, $import);

        $created = $this->imports->accept($import, $data);

        Inertia::flash('toast', [
            'type' => 'success',
            'message' => $created === 1 ? '1 compra lançada.' : "{$created} compras lançadas.",
        ]);

        return redirect()->route('cards.show', ['account' => $import->account_id]);
    }

    public function destroy(Request $request, StatementImport $import): RedirectResponse
    {
        $this->ensureOwner($request, $import);
        $cardId = $import->account_id;

        $this->imports->discard($import);

        return redirect()->route('cards.show', ['account' => $cardId]);
    }

    private function ensureOwner(Request $request, StatementImport $import): string
    {
        $userId = (string) $request->user()?->getAuthIdentifier();

        abort_unless($import->user_id === $userId, 404);

        return $userId;
    }
}
