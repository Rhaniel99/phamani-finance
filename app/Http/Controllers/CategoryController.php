<?php

namespace App\Http\Controllers;

use App\DTOs\Category\StoreCategoryData;
use App\Interfaces\Services\ICategoryService;
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
}
