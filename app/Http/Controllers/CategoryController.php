<?php

namespace App\Http\Controllers;

use App\DTOs\Category\StoreCategoryData;
use App\DTOs\Category\UpdateCategoryData;
use App\Interfaces\Services\ICategoryService;
use App\Models\Category;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;

class CategoryController extends Controller
{
    public function __construct(
        protected ICategoryService $service,
    ) {}

    public function store(Request $request, StoreCategoryData $data): RedirectResponse
    {
        $this->service->create((string) $request->user()?->getAuthIdentifier(), $data);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Categoria criada com sucesso!']);

        return back();
    }

    public function update(Request $request, Category $category, UpdateCategoryData $data): RedirectResponse
    {
        abort_unless($category->user_id === (string) $request->user()?->getAuthIdentifier(), 404);

        $this->service->update($category, $data);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Categoria atualizada!']);

        return back();
    }
}
