<?php

namespace App\Http\Controllers;

use App\Interfaces\Services\ITagService;
use App\Models\Tag;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;

/**
 * Gerenciar tags: renomear (ou juntar duas) e apagar. Criar é pelo formulário da transação.
 */
class TagController extends Controller
{
    public function __construct(
        protected ITagService $tags,
    ) {}

    public function update(Request $request, Tag $tag): RedirectResponse
    {
        $this->ensureOwner($request, $tag);

        $data = $request->validate(['name' => ['required', 'string', 'max:40']]);

        $merged = $this->tags->slug($data['name']) !== $tag->slug
            && Tag::query()->where('user_id', $tag->user_id)->where('slug', $this->tags->slug($data['name']))->exists();

        $this->tags->rename($tag, $data['name']);

        Inertia::flash('toast', ['type' => 'success', 'message' => $merged ? 'Tags juntadas!' : 'Tag renomeada!']);

        return back();
    }

    public function destroy(Request $request, Tag $tag): RedirectResponse
    {
        $this->ensureOwner($request, $tag);

        $this->tags->delete($tag);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Tag apagada (as transações continuam).']);

        return back();
    }

    private function ensureOwner(Request $request, Tag $tag): void
    {
        abort_unless($tag->user_id === (string) $request->user()?->getAuthIdentifier(), 404);
    }
}
